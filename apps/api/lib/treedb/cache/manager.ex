defmodule TreeDb.Cache.Manager do
  @moduledoc false
  use GenServer

  alias TreeDb.{Cache, Observability.Metrics}
  alias TreeDb.Runtime.Resources

  @managed [
    {TreeDb.RepositoryCache, :repo_doc},
    {TreeDb.Graph.IndexCache, :graph_index}
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    schedule_sample()
    {:ok, %{}}
  end

  def handle_info(:sample, state) do
    publish_runtime()
    rebalance_caches()
    schedule_sample()
    {:noreply, state}
  end

  def snapshot do
    %{
      runtime: Resources.memory_snapshot(),
      caches:
        Map.new(@managed, fn {table, kind} ->
          {kind, Cache.stats(table)}
        end)
    }
  end

  defp rebalance_caches do
    pressure? = Resources.cache_pressure?()

    Enum.each(@managed, fn {table, kind} ->
      max_bytes = Resources.cache_budget_for(kind)

      if pressure? or is_integer(max_bytes) do
        Cache.evict(table, %{max_entries: nil, max_bytes: max_bytes && trunc(max_bytes * 0.8)})
      end
    end)
  end

  defp publish_runtime do
    snapshot = Resources.memory_snapshot()
    Metrics.put_gauge("treedb_runtime_cpu_budget", Resources.cpu_budget())
    Metrics.put_gauge("treedb_runtime_beam_memory_bytes", snapshot.beam_total_bytes)
    Metrics.put_gauge("treedb_runtime_ets_memory_bytes", snapshot.ets_bytes)
    Metrics.put_gauge("treedb_runtime_binary_memory_bytes", snapshot.binary_bytes)
    Metrics.put_gauge("treedb_runtime_process_memory_bytes", snapshot.process_bytes)
    Metrics.put_gauge("treedb_runtime_cache_budget_bytes", snapshot.cache_budget_bytes || 0)
    Metrics.put_gauge("treedb_runtime_memory_budget_bytes", snapshot.budget_bytes || 0)
    Metrics.put_gauge("treedb_cache_pressure", pressure_value(snapshot.pressure))
  end

  defp schedule_sample do
    interval = Resources.int_env("TREEDB_CACHE_SAMPLING_INTERVAL_MS", 1_000)
    Process.send_after(self(), :sample, interval)
  end

  defp pressure_value(:low), do: 0
  defp pressure_value(:moderate), do: 1
  defp pressure_value(:high), do: 2
  defp pressure_value(_), do: -1
end
