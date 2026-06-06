defmodule TreeDxWeb.RegistryControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    {:ok, token: token}
  end

  test "node and registry endpoints", %{token: token} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/node")

    assert json_response(conn, 200)["node"]["id"] == "node_local"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/registry/nodes")

    assert [%{"id" => "node_local"} | _] = json_response(conn, 200)["nodes"]
  end

  test "placement and mirror endpoints persist records", %{token: token} do
    repo_id = "repo_controller_registry"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/registry/repos/#{repo_id}/placement", %{})

    assert json_response(conn, 200)["placement"]["repositoryId"] == repo_id

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/mirrors", %{"targetNodeId" => "node_b"})

    assert json_response(conn, 200)["mirror"]["targetNodeId"] == "node_b"
  end
end
