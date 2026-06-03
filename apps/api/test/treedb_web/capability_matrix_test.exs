defmodule TreeDbWeb.CapabilityMatrixTest do
  use TreeDbWeb.ConnCase, async: false

  test "protected endpoints require authentication and capability", %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/capability-matrix-repo")
    create_git_repo!(repo_path)
    admin_token = dev_token!(conn)

    repo_id =
      register_repo!(build_conn(), admin_token, %{
        "name" => "capability-matrix-repo",
        "localPath" => repo_path
      })["repo"]["repoId"]

    unauthenticated = get(build_conn(), "/api/v1/repos/#{repo_id}")
    assert json_response(unauthenticated, 401)["error"]["code"] == "authentication_required"

    {:ok, _grant} =
      TreeDb.Capabilities.put_grant(%{
        "actorId" => "actor_readonly",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => ["repos:read"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      })

    readonly_token =
      dev_token!(build_conn(), %{"actorId" => "actor_readonly", "tenantId" => "tenant_demo"})

    denied =
      build_conn()
      |> auth_conn(readonly_token)
      |> post("/api/v1/repos/#{repo_id}/files/search", %{
        "ref" => "refs/heads/main",
        "paths" => ["docs/**"],
        "query" => "mvp provenance"
      })
      |> json!(403)

    assert denied["error"]["code"] == "permission_denied"
  end

  test "workspace patch and delete require distinct file capabilities", %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/capability-file-actions")
    create_git_repo!(repo_path)
    admin_token = dev_token!(conn)

    repo_id =
      register_repo!(build_conn(), admin_token, %{
        "name" => "capability-file-actions",
        "localPath" => repo_path
      })["repo"]["repoId"]

    write_token = actor_token_with_caps!("actor_patch_only", repo_id, ["files:write"])

    write_workspace =
      create_workspace!(build_conn(), write_token, repo_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/patch-only",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    build_conn()
    |> auth_conn(write_token)
    |> put("/api/v1/workspaces/#{write_workspace["workspaceId"]}/files?path=docs/patch.md", %{
      "content" => "before\n"
    })
    |> json!(200)

    patch = """
    --- a/docs/patch.md
    +++ b/docs/patch.md
    @@ -1,1 +1,1 @@
    -before
    +after
    """

    patched =
      build_conn()
      |> auth_conn(write_token)
      |> patch(
        "/api/v1/workspaces/#{write_workspace["workspaceId"]}/files?path=docs/patch.md",
        %{
          "patch" => patch
        }
      )
      |> json!(200)

    assert patched["file"]["sha"] =~ "blake3:"

    delete_denied =
      build_conn()
      |> auth_conn(write_token)
      |> delete(
        "/api/v1/workspaces/#{write_workspace["workspaceId"]}/files?path=docs/guide.md",
        %{}
      )
      |> json!(409)

    assert delete_denied["error"]["code"] == "workspace_revoked"

    delete_token = actor_token_with_caps!("actor_delete_only", repo_id, ["files:delete"])

    delete_workspace =
      create_workspace!(build_conn(), delete_token, repo_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/delete-only",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    deleted =
      build_conn()
      |> auth_conn(delete_token)
      |> delete(
        "/api/v1/workspaces/#{delete_workspace["workspaceId"]}/files?path=docs/guide.md",
        %{}
      )
      |> json!(200)

    assert deleted["status"] == "deleted"

    patch_denied =
      build_conn()
      |> auth_conn(delete_token)
      |> patch(
        "/api/v1/workspaces/#{delete_workspace["workspaceId"]}/files?path=docs/guide.md",
        %{
          "patch" => patch
        }
      )
      |> json!(409)

    assert patch_denied["error"]["code"] == "workspace_revoked"
  end

  defp actor_token_with_caps!(actor_id, repo_id, caps) do
    {:ok, _grant} =
      TreeDb.Capabilities.put_grant(%{
        "actorId" => actor_id,
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => ["repos:read", "repos:write", "workspace:create" | caps],
        "refs" => ["refs/heads/*"],
        "paths" => ["docs/**"]
      })

    dev_token!(build_conn(), %{"actorId" => actor_id, "tenantId" => "tenant_demo"})
  end
end
