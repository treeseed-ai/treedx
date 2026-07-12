defmodule TreeDxWeb.HealthControllerTest do
  use TreeDxWeb.ConnCase, async: false
  import TreeDxPublicHygieneAssertions

  test "health and version endpoints", %{conn: conn} do
    conn = get(conn, "/api/v1/health")
    health = json_response(conn, 200)
    assert health["status"] == "ok"
    assert health["dataDir"] == "redacted"
    assert_public_hygiene!(health)

    conn = get(build_conn(), "/api/v1/version")
    assert json_response(conn, 200)["version"] == "0.2.40"
  end

  test "readiness and public deep health are sanitized" do
    readiness =
      build_conn()
      |> get("/api/v1/ready")
      |> json_response(200)

    assert readiness["readiness"]["status"] == "ready"
    assert_public_hygiene!(readiness)

    health =
      build_conn()
      |> get("/api/v1/health/deep")
      |> json_response(200)

    assert health["health"]["status"] in ["healthy", "degraded"]
    assert_public_hygiene!(health)
  end

  test "admin deep health requires policy read" do
    build_conn()
    |> get("/api/v1/admin/health/deep")
    |> json_response(401)

    token =
      build_conn()
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    health =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/admin/health/deep")
      |> json_response(200)

    assert health["health"]["status"] in ["healthy", "degraded"]
    assert_public_hygiene!(health)
  end
end
