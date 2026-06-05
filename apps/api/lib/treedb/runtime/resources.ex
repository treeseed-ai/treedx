defmodule TreeDb.Runtime.Resources do
  @moduledoc false

  def cpu_budget do
    int_env("TREEDB_RUNTIME_CPU_BUDGET", System.schedulers_online())
  end

  def memory_budget_bytes do
    case System.get_env("TREEDB_RUNTIME_MEMORY_BUDGET_MB") do
      nil -> nil
      "" -> nil
      value -> parse_positive_int(value) && parse_positive_int(value) * 1_048_576
    end
  end

  def cache_budget_bytes do
    case memory_budget_bytes() do
      nil ->
        nil

      budget ->
        fraction = float_env("TREEDB_CACHE_MEMORY_FRACTION", 0.25)
        min_free = int_env("TREEDB_CACHE_MIN_FREE_MEMORY_MB", 512) * 1_048_576
        max(trunc((budget - min_free) * fraction), 0)
    end
  end

  def cache_budget_for(kind) do
    with total when is_integer(total) and total > 0 <- cache_budget_bytes() do
      weights = %{
        repo_doc: int_env("TREEDB_REPO_DOC_CACHE_MEMORY_WEIGHT", 5),
        graph_index: int_env("TREEDB_GRAPH_INDEX_CACHE_MEMORY_WEIGHT", 3),
        artifact_index: int_env("TREEDB_ARTIFACT_INDEX_CACHE_MEMORY_WEIGHT", 1)
      }

      total_weight = Enum.sum(Map.values(weights))
      div(total * Map.get(weights, kind, 1), max(total_weight, 1))
    else
      _ -> nil
    end
  end

  def memory_snapshot do
    memory = :erlang.memory()
    budget = memory_budget_bytes()
    cache_budget = cache_budget_bytes()
    total = Keyword.get(memory, :total, 0)

    %{
      budget_bytes: budget,
      cache_budget_bytes: cache_budget,
      beam_total_bytes: total,
      ets_bytes: Keyword.get(memory, :ets, 0),
      process_bytes: Keyword.get(memory, :processes, 0),
      binary_bytes: Keyword.get(memory, :binary, 0),
      system_bytes: Keyword.get(memory, :system, 0),
      free_budget_bytes: if(budget, do: budget - total),
      pressure: pressure(budget, total)
    }
  end

  def cache_pressure?, do: memory_snapshot().pressure in [:moderate, :high]

  def worker_pool_size(:repository_query),
    do: int_env("TREEDB_REPOSITORY_QUERY_POOL_SIZE", max(2, cpu_budget() * 2))

  def worker_pool_size(:workspace_mutation),
    do: int_env("TREEDB_WORKSPACE_WORKER_POOL_SIZE", max(2, cpu_budget() * 2))

  def worker_pool_size(:graph), do: int_env("TREEDB_GRAPH_WORKER_POOL_SIZE", max(1, cpu_budget()))

  def worker_pool_size(:snapshot),
    do: int_env("TREEDB_SNAPSHOT_WORKER_POOL_SIZE", max(1, div(cpu_budget(), 2)))

  def worker_pool_size(:import),
    do: int_env("TREEDB_IMPORT_WORKER_POOL_SIZE", max(1, div(cpu_budget(), 2)))

  def worker_pool_max_queue(:repository_query),
    do: int_env("TREEDB_REPOSITORY_QUERY_MAX_QUEUE", 2_000)

  def worker_pool_max_queue(:workspace_mutation),
    do: int_env("TREEDB_WORKSPACE_MUTATION_MAX_QUEUE", 1_000)

  def worker_pool_max_queue(:graph), do: int_env("TREEDB_GRAPH_MAX_QUEUE", 500)
  def worker_pool_max_queue(:snapshot), do: int_env("TREEDB_SNAPSHOT_MAX_QUEUE", 200)
  def worker_pool_max_queue(:import), do: int_env("TREEDB_IMPORT_MAX_QUEUE", 100)

  def worker_pool_queue_timeout(:repository_query),
    do: int_env("TREEDB_REPOSITORY_QUERY_QUEUE_TIMEOUT_MS", 30_000)

  def worker_pool_queue_timeout(:workspace_mutation),
    do: int_env("TREEDB_WORKSPACE_MUTATION_QUEUE_TIMEOUT_MS", 30_000)

  def worker_pool_queue_timeout(:graph), do: int_env("TREEDB_GRAPH_QUEUE_TIMEOUT_MS", 45_000)

  def worker_pool_queue_timeout(:snapshot),
    do: int_env("TREEDB_SNAPSHOT_QUEUE_TIMEOUT_MS", 60_000)

  def worker_pool_queue_timeout(:import), do: int_env("TREEDB_IMPORT_QUEUE_TIMEOUT_MS", 60_000)

  def execution_timeout_ms, do: int_env("TREEDB_HEAVY_OPERATION_EXECUTION_TIMEOUT_MS", 0)

  def int_env(name, default), do: parse_positive_int(System.get_env(name)) || default

  defp float_env(name, default) do
    case Float.parse(System.get_env(name, "")) do
      {value, _} when value >= 0.0 -> value
      _ -> default
    end
  end

  defp parse_positive_int(nil), do: nil
  defp parse_positive_int(""), do: nil

  defp parse_positive_int(value) do
    case Integer.parse(to_string(value)) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
  end

  defp pressure(nil, _total), do: :unknown
  defp pressure(budget, total) when total >= budget, do: :high
  defp pressure(budget, total) when total / budget >= 0.85, do: :moderate
  defp pressure(_budget, _total), do: :low
end
