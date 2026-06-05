defmodule TreeDb.Graph.IndexCache do
  @moduledoc false
  use GenServer

  alias TreeDb.Cache

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    Cache.ensure_table(@table)
    {:ok, %{}}
  end

  def reset!, do: Cache.reset(@table)

  def get_or_load(repo_id, graph_version, loader) do
    if Cache.enabled?("TREEDB_GRAPH_INDEX_CACHE_ENABLED", true) and Process.whereis(__MODULE__) do
      Cache.get_or_load(
        @table,
        {repo_id, graph_version},
        Cache.int_env("TREEDB_GRAPH_INDEX_CACHE_TTL_MS", 300_000),
        Cache.int_env("TREEDB_GRAPH_INDEX_CACHE_MAX_ENTRIES", 128),
        cache_max_bytes(),
        loader
      )
    else
      loader.()
    end
  end

  def put(index) when is_map(index) do
    manifest = index["manifest"] || %{}
    repo_id = manifest["repoId"]
    graph_version = manifest["graphVersion"]

    if is_binary(repo_id) and is_binary(graph_version) do
      Cache.put(
        @table,
        {repo_id, graph_version},
        index,
        System.monotonic_time(:millisecond),
        Cache.int_env("TREEDB_GRAPH_INDEX_CACHE_MAX_ENTRIES", 128),
        cache_max_bytes()
      )
    end

    :ok
  end

  defp cache_max_bytes do
    case System.get_env("TREEDB_GRAPH_INDEX_CACHE_MAX_BYTES") do
      nil ->
        TreeDb.Runtime.Resources.cache_budget_for(:graph_index)

      "" ->
        TreeDb.Runtime.Resources.cache_budget_for(:graph_index)

      value ->
        parse_positive_int(value) || TreeDb.Runtime.Resources.cache_budget_for(:graph_index)
    end
  end

  defp parse_positive_int(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end
end
