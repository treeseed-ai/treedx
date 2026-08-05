defmodule TreeDx.Audit.Writer do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    Process.flag(:priority, :low)
    {:ok, %{queue: [], size: 0}, flush_interval()}
  end

  def append(event) do
    writer = Process.whereis(__MODULE__)

    if async_enabled?() and writer do
      normalized = normalize_event(event)
      GenServer.cast(writer, {:append, event})
      {:ok, normalized}
    else
      TreeDx.Store.append_audit_event(event)
    end
  end

  defp normalize_event(value) when is_map(value) do
    Map.new(value, fn {key, item} -> {normalize_key(key), normalize_event(item)} end)
  end

  defp normalize_event(value) when is_list(value), do: Enum.map(value, &normalize_event/1)
  defp normalize_event(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  def flush do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :flush, 30_000)
    else
      :ok
    end
  end

  def handle_cast({:append, event}, state) do
    if state.size >= queue_max() do
      TreeDx.Observability.Metrics.incr("treedx_audit_sync_fallback_total")
      _ = TreeDx.Store.append_audit_event(event)
      {:noreply, state, flush_interval()}
    else
      queue = [event | state.queue]
      size = state.size + 1
      state = %{state | queue: queue, size: size}
      TreeDx.Observability.Metrics.put_gauge("treedx_audit_queue_depth", size)

      if size >= batch_size() do
        {:noreply, flush_state(state), flush_interval()}
      else
        {:noreply, state, flush_interval()}
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

    case TreeDx.Store.append_audit_events(events) do
      {:ok, _records} ->
        elapsed =
          System.monotonic_time(:microsecond)
          |> Kernel.-(started)
          |> Kernel./(1000)

        TreeDx.Observability.Metrics.incr("treedx_audit_flush_total", %{}, length(events))
        TreeDx.Observability.Metrics.observe("treedx_audit_flush_duration_ms", elapsed)

      {:error, _error} ->
        TreeDx.Observability.Metrics.incr(
          "treedx_audit_append_failures_total",
          %{},
          length(events)
        )
    end

    TreeDx.Observability.Metrics.put_gauge("treedx_audit_queue_depth", 0)
    %{state | queue: [], size: 0}
  end

  defp async_enabled? do
    default = if System.get_env("MIX_ENV") == "test", do: "false", else: "true"
    System.get_env("TREEDX_AUDIT_ASYNC", default) in ["true", "1", "yes", "on"]
  end

  defp batch_size, do: int_env("TREEDX_AUDIT_BATCH_SIZE", 100)
  defp flush_interval, do: int_env("TREEDX_AUDIT_FLUSH_INTERVAL_MS", 100)
  defp queue_max, do: int_env("TREEDX_AUDIT_QUEUE_MAX", 10_000)

  defp int_env(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end
end
