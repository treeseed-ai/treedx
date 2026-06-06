defmodule TreeDxWeb.AuthPolicyControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    {:ok, token: token}
  end

  test "auth mode, capabilities, grants, audit, and federation plan endpoints", %{token: token} do
    conn = get(build_conn(), "/api/v1/auth/mode")
    assert json_response(conn, 200)["mode"] == "dev"

    conn =
      authed(token)
      |> get("/api/v1/policy/capabilities")

    assert "query:federated" in json_response(conn, 200)["capabilities"]

    conn =
      authed(token)
      |> post("/api/v1/policy/grants", %{
        "actorId" => "actor_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => ["repo_allowed"],
        "capabilities" => ["files:search", "query:federated"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      })

    assert json_response(conn, 200)["grant"]["actorId"] == "actor_limited"

    conn =
      authed(token)
      |> get("/api/v1/audit/events", %{"eventType" => "policy.grant.updated"})

    assert is_list(json_response(conn, 200)["events"])

    {:ok, _} =
      TreeDx.Store.put_repository_placement(%{
        repositoryId: "repo_allowed",
        primaryNodeId: "node_local",
        mirrorNodeIds: [],
        readPolicy: "primary_or_mirror",
        writePolicy: "primary_only",
        migrationState: "stable"
      })

    conn =
      authed(token)
      |> post("/api/v1/federation/query/plan", %{
        "repoIds" => ["repo_allowed", "repo_hidden"],
        "refs" => %{"repo_allowed" => "refs/heads/main", "repo_hidden" => "refs/heads/main"},
        "paths" => %{"repo_allowed" => ["docs/**"], "repo_hidden" => ["secret/**"]},
        "capabilities" => ["files:search"]
      })

    body = json_response(conn, 200)
    assert body["executable"] == false
    assert [%{"repoId" => "repo_allowed"}] = body["effectiveScope"]["repos"]
  end

  defp authed(token) do
    build_conn() |> put_req_header("authorization", "Bearer #{token}")
  end
end
