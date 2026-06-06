defmodule TreeDxWeb.ObservabilityRequestTest do
  use TreeDxWeb.ConnCase, async: false

  alias TreeDx.Observability.Metrics

  setup do
    Metrics.reset!()
    :ok
  end

  test "echoes request ids and records normalized HTTP metrics" do
    conn =
      build_conn()
      |> put_req_header("x-request-id", "req_test")
      |> get("/api/v1/health")

    assert get_resp_header(conn, "x-request-id") == ["req_test"]

    metrics = Metrics.snapshot()
    assert Enum.any?(metrics.counters, &(&1.labels["route"] == "/api/v1/health"))
  end
end
