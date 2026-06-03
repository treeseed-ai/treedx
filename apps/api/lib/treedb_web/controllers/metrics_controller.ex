defmodule TreeDbWeb.MetricsController do
  use Phoenix.Controller, formats: [:json]

  import TreeDbWeb.ControllerHelpers

  def json(conn, _params) do
    ok(conn, %{metrics: TreeDb.Observability.Metrics.snapshot()})
  end

  def prometheus(conn, _params) do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, TreeDb.Observability.Metrics.prometheus())
  end
end
