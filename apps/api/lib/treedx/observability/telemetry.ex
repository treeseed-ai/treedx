defmodule TreeDx.Observability.Telemetry do
  @moduledoc false
  use GenServer

  alias TreeDx.Observability.Metrics

  @handler_id "treedx-observability-telemetry"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    :telemetry.detach(@handler_id)

    :telemetry.attach(
      @handler_id,
      [:phoenix, :endpoint, :stop],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, state}
  end

  def handle_event([:phoenix, :endpoint, :stop], measurements, metadata, _config) do
    conn = metadata[:conn]
    duration_ms = System.convert_time_unit(measurements[:duration] || 0, :native, :millisecond)
    route = normalized_route(conn)
    method = (conn && conn.method) || "UNKNOWN"
    status = (conn && conn.status) || 0
    status_class = status_class(status)
    labels = %{method: method, route: route, status_class: status_class}

    Metrics.incr("treedx_http_requests_total", labels)

    Metrics.observe(
      "treedx_http_request_duration_ms",
      duration_ms,
      Map.delete(labels, :status_class)
    )

    if status >= 400 do
      Metrics.incr("treedx_http_errors_total", Map.put(labels, :error_code, error_code(conn)))
    end

    :ok
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  defp normalized_route(nil), do: "unknown"

  defp normalized_route(conn) do
    conn.private[:phoenix_route] || conn.request_path || "unknown"
  end

  defp status_class(status) when is_integer(status) and status >= 100 do
    "#{div(status, 100)}xx"
  end

  defp status_class(_status), do: "unknown"

  defp error_code(conn) do
    conn.assigns[:treedx_error_code] || "unknown"
  rescue
    _ -> "unknown"
  end
end
