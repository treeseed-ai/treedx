defmodule TreeDb.Audit.Writer do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    {:ok, %{queue: []}, flush_interval()}
  end

  def append(event) do
    if async_enabled?() and Process.whereis(__MODULE__) do
      case GenServer.call(__MODULE__, {:append, event}, 5_000) do
        :ok ->
          {:ok, normalize_event(event)}

        :sync ->
          TreeDb.Observability.Metrics.incr("treedb_audit_sync_fallback_total")
          TreeDb.Store.append_audit_event(event)
      end
    else
      TreeDb.Store.append_audit_event(event)
    end
  end

  defp normalize_event(event) do
    event
    |> Jason.encode!()
    |> Jason.decode!()
  end

  def flush do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :flush, 30_000)
    else
      :ok
    end
  end

  def handle_call({:append, event}, _from, state) do
    if length(state.queue) >= queue_max() do
      {:reply, :sync, state, flush_interval()}
    else
      queue = [event | state.queue]
      state = %{state | queue: queue}
      TreeDb.Observability.Metrics.put_gauge("treedb_audit_queue_depth", length(queue))

      if length(queue) >= batch_size() do
        {:reply, :ok, flush_state(state), flush_interval()}
      else
        {:reply, :ok, state, flush_interval()}
      end
    end
  end

  def handle_call(:flush, _from, state), do: {:reply, :ok, flush_state(state), flush_interval()}

  def handle_info(:timeout, state), do: {:noreply, flush_state(state), flush_interval()}

  def terminate(_reason, state) do
    flush_state(state)
    :ok
  end

  defp flush_state(%{queue: []} = state), do: state

  defp flush_state(state) do
    events = Enum.reverse(state.queue)
    started = System.monotonic_time(:microsecond)

    case TreeDb.Store.append_audit_events(events) do
      {:ok, _records} ->
        elapsed =
          System.monotonic_time(:microsecond)
          |> Kernel.-(started)
          |> Kernel./(1000)

        TreeDb.Observability.Metrics.incr("treedb_audit_flush_total", %{}, length(events))
        TreeDb.Observability.Metrics.observe("treedb_audit_flush_duration_ms", elapsed)

      {:error, _error} ->
        TreeDb.Observability.Metrics.incr(
          "treedb_audit_append_failures_total",
          %{},
          length(events)
        )
    end

    TreeDb.Observability.Metrics.put_gauge("treedb_audit_queue_depth", 0)
    %{state | queue: []}
  end

  defp async_enabled? do
    default = if System.get_env("MIX_ENV") == "test", do: "false", else: "true"
    System.get_env("TREEDB_AUDIT_ASYNC", default) in ["true", "1", "yes", "on"]
  end

  defp batch_size, do: int_env("TREEDB_AUDIT_BATCH_SIZE", 100)
  defp flush_interval, do: int_env("TREEDB_AUDIT_FLUSH_INTERVAL_MS", 100)
  defp queue_max, do: int_env("TREEDB_AUDIT_QUEUE_MAX", 10_000)

  defp int_env(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end
end
