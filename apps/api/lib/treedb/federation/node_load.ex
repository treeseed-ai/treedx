defmodule TreeDb.Federation.NodeLoad do
  @moduledoc false

  alias TreeDb.Observability.Metrics

  @table :treedb_federation_node_load

  def get(node_id) do
    ensure_table!()

    case :ets.lookup(@table, node_id) do
      [{^node_id, loaded_at, payload}] ->
        if fresh?(loaded_at), do: {:ok, payload}, else: refresh(node_id)

      _ ->
        refresh(node_id)
    end
  end

  def refresh(node_id) do
    ensure_table!()
    started = System.monotonic_time(:millisecond)

    result =
      with {:ok, peer} when is_map(peer) <- TreeDb.Store.get_federation_peer(node_id),
           base_url when is_binary(base_url) and base_url != "" <- peer["baseUrl"],
           {:ok, status, _headers, body} <-
             TreeDb.Federation.HttpClient.get_json(
               node_id,
               base_url,
               "/api/v1/internal/federation/health",
               "health"
             ),
           true <- status in 200..299,
           {:ok, decoded} <- Jason.decode(body) do
        load = sanitize(decoded)
        :ets.insert(@table, {node_id, monotonic_ms(), load})
        {:ok, load}
      else
        _ -> {:error, :unknown}
      end

    Metrics.incr("treedb_federation_remote_load_refresh_total", %{node: node_id})

    Metrics.observe("treedb_federation_remote_load_refresh_duration_ms", elapsed(started), %{
      node: node_id
    })

    if match?({:error, _}, result) do
      Metrics.incr("treedb_federation_remote_load_refresh_failures_total", %{node: node_id})
    end

    result
  end

  def pool_load(node_id, pool) do
    with {:ok, load} <- get(node_id) do
      {:ok, load_for_pool(load, pool)}
    end
  end

  def local_pool_load(pool) do
    snapshot = TreeDb.Runtime.Pool.pool_snapshot(pool) || %{}
    load_for_pool(%{"pools" => %{to_string(pool) => atomize_pool(snapshot)}}, pool)
  end

  def compare_candidates(candidates, pool) do
    Enum.sort_by(candidates, fn candidate ->
      load = candidate["load"] || load_for_candidate(candidate, pool)
      {pressure_rank(load["pressure"]), load["queueDepth"] || 0, load["active"] || 0}
    end)
  end

  def load_for_candidate(%{"servedByNodeId" => node_id, "source" => source}, pool)
      when source in ["local", "mirror"] do
    if node_id == TreeDb.Federation.NodeIdentity.node_id() do
      local_pool_load(pool)
    else
      case pool_load(node_id, pool) do
        {:ok, load} -> load
        _ -> unknown_load(pool)
      end
    end
  end

  def load_for_candidate(%{"servedByNodeId" => node_id}, pool) do
    case pool_load(node_id, pool) do
      {:ok, load} -> load
      _ -> unknown_load(pool)
    end
  end

  def load_for_candidate(_candidate, pool), do: unknown_load(pool)

  def pressure_rank("low"), do: 0
  def pressure_rank(:low), do: 0
  def pressure_rank("moderate"), do: 1
  def pressure_rank(:moderate), do: 1
  def pressure_rank("high"), do: 2
  def pressure_rank(:high), do: 2
  def pressure_rank("saturated"), do: 3
  def pressure_rank(:saturated), do: 3
  def pressure_rank(_), do: 1

  def pressure_at_or_above?(pressure, threshold),
    do: pressure_rank(pressure) >= pressure_rank(threshold)

  def unknown_load(pool) do
    %{
      "pool" => to_string(pool),
      "pressure" => "moderate",
      "queueDepth" => nil,
      "active" => nil,
      "size" => nil,
      "unknown" => true
    }
  end

  defp load_for_pool(%{"pools" => pools}, pool) when is_map(pools) do
    key = to_string(pool)
    pool_info = pools[key] || pools[camelize_pool(key)] || %{}

    %{
      "pool" => key,
      "pressure" => to_string(pool_info["pressure"] || pool_info[:pressure] || "moderate"),
      "queueDepth" =>
        pool_info["queueDepth"] || pool_info[:queueDepth] || pool_info[:queue_depth],
      "queueMax" => pool_info["queueMax"] || pool_info[:queueMax] || pool_info[:queue_max],
      "active" => pool_info["active"] || pool_info[:active],
      "size" => pool_info["size"] || pool_info[:size],
      "availableSlots" => pool_info["availableSlots"] || pool_info[:availableSlots]
    }
  end

  defp load_for_pool(_load, pool), do: unknown_load(pool)

  defp atomize_pool(snapshot) do
    snapshot
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp sanitize(decoded) do
    %{
      "nodeId" => decoded["nodeId"],
      "federation" => decoded["federation"] || %{},
      "runtime" => Map.take(decoded["runtime"] || %{}, ["pressure"]),
      "pools" => decoded["pools"] || %{}
    }
  end

  defp camelize_pool("repository_query"), do: "repositoryQuery"
  defp camelize_pool("workspace_mutation"), do: "workspaceMutation"
  defp camelize_pool(pool), do: pool

  defp fresh?(loaded_at), do: monotonic_ms() - loaded_at <= ttl_ms()
  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp elapsed(started), do: monotonic_ms() - started

  defp ttl_ms do
    case Integer.parse(System.get_env("TREEDB_FEDERATION_REMOTE_LOAD_TTL_MS", "2000")) do
      {ttl, _} when ttl > 0 -> ttl
      _ -> 2_000
    end
  end

  defp ensure_table! do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end

    :ok
  rescue
    ArgumentError -> :ok
  end
end
