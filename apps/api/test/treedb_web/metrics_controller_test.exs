defmodule TreeDbWeb.MetricsControllerTest do
  use TreeDbWeb.ConnCase, async: false

  import TreeDbPublicHygieneAssertions

  alias TreeDb.Observability.Metrics

  setup do
    Metrics.reset!()
    :ok
  end

  test "returns prometheus and JSON metrics without sensitive labels", %{conn: conn} do
    get(conn, "/api/v1/health") |> json_response(200)

    prometheus =
      build_conn()
      |> get("/metrics")
      |> response(200)

    assert prometheus =~ "treedb_http_requests_total"
    assert prometheus =~ "route=\"/api/v1/health\""
    refute prometheus =~ "actor_"
    refute prometheus =~ TreeDb.Store.data_dir()

    json =
      build_conn()
      |> get("/api/v1/metrics")
      |> json_response(200)

    assert json["ok"] == true
    assert is_list(json["metrics"]["counters"])
    assert_public_hygiene!(json)
  end

  test "records auth failures and capability denials" do
    build_conn()
    |> put_req_header("authorization", "Bearer invalid")
    |> get("/api/v1/repos")
    |> json_response(401)

    token =
      build_conn()
      |> post("/api/v1/auth/dev-token", %{"actorId" => "actor_limited"})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> get("/api/v1/repos")
    |> json_response(403)

    metrics = Metrics.snapshot()
    assert Enum.any?(metrics.counters, &(&1.name == "treedb_auth_failures_total"))
    assert Enum.any?(metrics.counters, &(&1.name == "treedb_capability_denials_total"))
  end
end
