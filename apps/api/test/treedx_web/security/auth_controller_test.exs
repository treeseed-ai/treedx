defmodule TreeDxWeb.AuthControllerTest do
  use TreeDxWeb.ConnCase, async: false

  test "whoami and dev token", %{conn: conn} do
    conn = get(conn, "/api/v1/auth/whoami")
    assert json_response(conn, 200)["authenticated"] == false

    conn = post(build_conn(), "/api/v1/auth/dev-token", %{})
    body = json_response(conn, 200)
    assert body["accessToken"] =~ "treedx_dev_"
  end

  test "effective scope defaults in dev mode", %{conn: conn} do
    conn = get(conn, "/api/v1/policy/effective-scope")
    assert "repos:read" in json_response(conn, 200)["effectiveScope"]["capabilities"]
  end
end
