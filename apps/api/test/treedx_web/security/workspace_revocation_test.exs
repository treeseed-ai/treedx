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

    {:ok, _cleanup_grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "actor_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => ["files:read"],
        "refs" => ["refs/heads/*"],
        "paths" => ["docs/**"]
      })

    # Metadata must not restore productive authority or mutate the retained
    # revoked resource. Capture both owning service and real endpoint outcomes
    # before asserting, so either boundary's failure remains observable.
    principal = %{"actorId" => "actor_limited", "tenantId" => "tenant_demo"}
    {:ok, retained} = TreeDx.Store.get_workspace(workspace_id)
    direct = TreeDx.Workspaces.get(workspace_id, principal)

    metadata_conn =
      build_conn()
      |> auth_conn(limited_token)
      |> get("/api/v1/workspaces/#{workspace_id}")

    assert {:ok, %{workspaceId: ^workspace_id, repoId: ^repo_id, status: "quarantined"}} =
             direct

    assert metadata_conn.status == 200
    metadata = Jason.decode!(metadata_conn.resp_body)
    assert metadata["workspaceId"] == workspace_id
    assert metadata["repoId"] == repo_id
    assert metadata["status"] == "quarantined"
    assert {:ok, ^retained} = TreeDx.Store.get_workspace(workspace_id)

    assert {:error, %{code: "permission_denied"}} =
             TreeDx.Workspaces.get(workspace_id, %{principal | "actorId" => "foreign_actor"})

    assert {:ok, ^retained} = TreeDx.Store.get_workspace(workspace_id)

    closed =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/workspaces/#{workspace_id}/close", %{})
      |> json!(200)

    assert closed["status"] == "closed"
    refute File.exists?(Path.join([data_dir, "workspaces", "active", workspace_id]))

    {:ok, retained_closed} = TreeDx.Store.get_workspace(workspace_id)

    for _ <- 1..2 do
      assert {:ok, %{workspaceId: ^workspace_id, repoId: ^repo_id, status: "closed"}} =
               TreeDx.Workspaces.get(workspace_id, principal)

      readback =
        build_conn()
        |> auth_conn(limited_token)
        |> get("/api/v1/workspaces/#{workspace_id}")
        |> json!(200)

      assert readback["workspaceId"] == workspace_id
      assert readback["repoId"] == repo_id
      assert readback["status"] == "closed"
      assert {:ok, ^retained_closed} = TreeDx.Store.get_workspace(workspace_id)
      refute File.exists?(Path.join([data_dir, "workspaces", "active", workspace_id]))
    end
  end
end
