defmodule TreeDxWeb.FederationCatalogControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    {:ok, token: token}
  end

  test "catalog exposes logical repository metadata without local paths", %{token: token} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{
        "repositoryName" => "catalog-repo",
        "createIfMissing" => true
      })

    assert json_response(conn, 200)["repo"]["repositoryName"] == "catalog-repo"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/federation/catalog")

    body = json_response(conn, 200)
    encoded = Jason.encode!(body)
    assert body["catalog"]["node"]["nodeId"] == "node_local"
    assert encoded =~ "catalog-repo"
    refute encoded =~ "localPath"
    refute encoded =~ TreeDx.Store.data_dir()
  end

  test "peer trust can be changed without restart", %{token: token} do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/federation/nodes/register", %{
        "nodeId" => "node_b",
        "baseUrl" => "http://node-b.example.invalid",
        "trustStates" => ["registered"]
      })

    peer = json_response(conn, 200)["peer"]
    assert peer["id"] == "node_b"
    assert peer["nodeId"] == "node_b"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/federation/peers/node_b/trust", %{
        "trustStates" => ["trusted_for_catalog", "trusted_for_query"]
      })

    assert "trusted_for_query" in json_response(conn, 200)["peer"]["trustStates"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/federation/peers/node_b")

    peer = json_response(conn, 200)["peer"]
    assert peer["nodeId"] == "node_b"
    assert "trusted_for_catalog" in peer["trustStates"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/federation/peers")

    assert Enum.any?(json_response(conn, 200)["peers"], &(&1["nodeId"] == "node_b"))
  end

  test "trusted federation mirror peer can be used as migration dry-run target", %{token: token} do
    repo_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{
        "repositoryName" => "migration-federation-repo",
        "createIfMissing" => true,
        "placement" => %{"primaryNodeId" => "node_a"}
      })

    repo_id = json_response(repo_conn, 200)["repo"]["repoId"]

    register_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/federation/nodes/register", %{
        "nodeId" => "node_b",
        "baseUrl" => "http://node-b.example.invalid",
        "trustStates" => ["registered"],
        "canMirrorRepos" => true
      })

    assert json_response(register_conn, 200)["peer"]["canMirrorRepos"] == true

    trust_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/federation/peers/node_b/trust", %{
        "trustStates" => ["registered", "trusted_for_catalog", "trusted_for_mirror"]
      })

    assert "trusted_for_mirror" in json_response(trust_conn, 200)["peer"]["trustStates"]

    migration_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/migrations", %{
        "sourceNodeId" => "node_a",
        "targetNodeId" => "node_b",
        "mode" => "primary_transfer",
        "dryRun" => true,
        "requireMirrorSynced" => false
      })

    body = json_response(migration_conn, 200)
    assert body["migration"]["targetNodeId"] == "node_b"
    assert body["migration"]["dryRun"] == true
  end
end
