defmodule TreeDx.Runtime.Pool.Snapshot do
  @moduledoc false

  @table :treedx_runtime_pool_snapshots

  def create! do
    :ets.new(@table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  def replace(state) do
    :ets.insert(@table, Enum.map(state, fn {pool, info} -> {pool, public_info(info)} end))
    :ok
  end

  def put(pool, info) do
    :ets.insert(@table, {normalize_pool(pool), public_info(info)})
    :ok
  end

  def get(pool) do
    case :ets.lookup(@table, normalize_pool(pool)) do
      [{_pool, info}] -> info
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def all do
    Map.new(:ets.tab2list(@table))
  rescue
    ArgumentError -> %{}
  end

  def pressure_for(%{active: active, size: size, queue_depth: queue_depth, queue_max: queue_max}) do
    active_ratio = safe_ratio(map_size(active), size)
    queue_ratio = safe_ratio(queue_depth, queue_max)

    cond do
      queue_ratio >= 0.9 -> :saturated
      active_ratio >= 0.9 or queue_ratio >= 0.6 -> :high
      active_ratio >= 0.7 or queue_ratio >= 0.25 -> :moderate
      true -> :low
    end
  end

  defp public_info(info) do
    %{
      size: info.size,
      active: map_size(info.active),
      queueDepth: info.queue_depth,
      queueMax: info.queue_max,
      activeMax: info.active_max,
      queueDepthMax: info.queue_depth_max,
      enqueued: info.enqueued,
      started: info.started,
      completed: info.completed,
      rejected: info.rejected,
      queueTimeouts: info.queue_timeouts,
      executionTimeouts: info.execution_timeouts,
      cancelled: info.cancelled,
      availableSlots: max(info.size - map_size(info.active), 0),
      pressure: to_string(pressure_for(info)),
      totalWaitMs: info.total_wait_ms,
      totalExecutionMs: info.total_execution_ms
    }
  end

  defp safe_ratio(_value, max) when max in [nil, 0], do: 0.0
  defp safe_ratio(value, max), do: value / max
  defp normalize_pool(pool) when is_atom(pool), do: pool
  defp normalize_pool(pool), do: pool |> to_string() |> String.to_existing_atom()
end
