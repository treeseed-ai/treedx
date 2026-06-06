defmodule TreeDxWeb.WorkspaceRevocationTest do
  use TreeDxWeb.ConnCase, async: false

  test "workspace operations quarantine after policy revocation", %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/workspace-revocation-repo")
    create_git_repo!(repo_path)

    admin_token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), admin_token, %{
        "name" => "workspace-revocation-repo",
        "localPath" => repo_path
      })["repo"]

    repo_id = repo["repoId"]

    {:ok, grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "actor_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => [
          "repos:read",
          "repos:write",
          "workspace:create",
          "files:read",
          "files:write",
          "files:delete",
          "files:search",
          "git:diff",
          "git:commit",
          "workspace:exec:read_only",
          "workspace:exec:verification",
          "workspace:exec:write_limited"
        ],
        "refs" => ["refs/heads/*"],
        "paths" => ["docs/**"]
      })

    limited_token =
      dev_token!(build_conn(), %{"actorId" => "actor_limited", "tenantId" => "tenant_demo"})

    workspace =
      create_workspace!(build_conn(), limited_token, repo_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/revoked",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    workspace_id = workspace["workspaceId"]
    assert is_binary(workspace["policyHash"])

    refresh =
      build_conn()
      |> auth_conn(admin_token)
      |> post("/api/v1/policy/refresh", %{
        "source" => "control_plane",
        "revocations" => [%{"id" => grant["id"], "reason" => "test_revocation"}]
      })
      |> json!(200)

    assert refresh["refreshed"] == true

    read =
      build_conn()
      |> auth_conn(limited_token)
      |> get("/api/v1/workspaces/#{workspace_id}/files", %{"path" => "docs/readme.md"})
      |> json!(409)

    assert read["error"]["code"] == "workspace_revoked"

    write =
      build_conn()
      |> auth_conn(limited_token)
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md", %{
        "content" => "# blocked"
      })
      |> json!(409)

    assert write["error"]["code"] == "workspace_revoked"

    exec =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{"cmd" => "true", "mode" => "read_only"})
      |> json!(409)

    assert exec["error"]["code"] == "workspace_revoked"

    quarantined =
      build_conn()
      |> auth_conn(admin_token)
      |> get("/api/v1/admin/workspaces/quarantined")
      |> json!(200)

    assert Enum.any?(quarantined["workspaces"], &(&1["workspaceId"] == workspace_id))

    audit =
      build_conn()
      |> auth_conn(admin_token)
      |> get("/api/v1/audit/events", %{"eventType" => "workspace.quarantined"})
      |> json!(200)

    assert Enum.any?(audit["events"], &(&1["workspaceId"] == workspace_id))
  end
end
