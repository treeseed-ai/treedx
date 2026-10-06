defmodule TreeDx.Federation.RouteCache do
  @moduledoc false
  use GenServer

  alias TreeDx.Cache

  @table __MODULE__
  @versions TreeDx.Federation.RouteCache.Versions

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    Cache.ensure_table(@table)

    :ets.new(@versions, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, state}
  end

  def get(repo_id, loader) when is_binary(repo_id) and is_function(loader, 0) do
    version = version(repo_id)

    result =
      Cache.get_or_load(
        @table,
        {repo_id, version},
        Cache.int_env("TREEDX_FEDERATION_ROUTE_CACHE_TTL_MS", 60_000),
        Cache.int_env("TREEDX_FEDERATION_ROUTE_CACHE_MAX_ENTRIES", 4_096),
        loader
      )

    if version == version(repo_id), do: result, else: get(repo_id, loader)
  end

  def invalidate(repo_id) when is_binary(repo_id) do
    old_version = version(repo_id)
    :ets.update_counter(@versions, {:repo, repo_id}, {2, 1}, {{:repo, repo_id}, 0})
    Cache.delete(@table, {repo_id, old_version})
  rescue
    ArgumentError -> :ok
  end

  def invalidate(_repo_id), do: reset()

  def reset do
    if :ets.whereis(@versions) != :undefined do
      :ets.update_counter(@versions, :global, {2, 1}, {:global, 0})
    end

    Cache.reset(@table)
  end

  defp version(repo_id) do
    {lookup_version(:global), lookup_version({:repo, repo_id})}
  end

  defp lookup_version(key) do
    case :ets.lookup(@versions, key) do
      [{^key, version}] -> version
      [] -> 0
    end
  rescue
    ArgumentError -> 0
  end
end
