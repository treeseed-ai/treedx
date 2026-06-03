defmodule TreeDbWeb.PushControllerTest do
  use TreeDbWeb.ConnCase, async: false

  setup %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/push-api")
    remote_path = Path.join(data_dir, "repos/bare/push-api-remote.git")
    create_git_repo!(repo_path)
    File.rm_rf!(remote_path)
    File.mkdir_p!(remote_path)
    git!(remote_path, ["init", "--bare"])
    token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "push-api",
        "localPath" => repo_path,
        "remoteUrl" => "file://#{remote_path}"
      })["repo"]

    {:ok, token: token, repo_id: repo["repoId"], remote_path: remote_path}
  end

  test "actor with git push can dry-run and push an allowed ref", %{
    token: token,
    repo_id: repo_id,
    remote_path: remote_path
  } do
    dry_run =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "dryRun" => true
      })
      |> json!(200)

    assert dry_run["push"]["status"] == "dry_run"
    assert dry_run["push"]["backend"] == "gix"
    assert_public_hygiene!(dry_run)

    pushed =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "dryRun" => false
      })
      |> json!(200)

    assert pushed["push"]["status"] == "pushed"
    assert pushed["push"]["updatedRefs"] == ["refs/heads/main"]
    assert git_bare!(remote_path, ["rev-parse", "refs/heads/main"]) =~ ~r/^[0-9a-f]{40}/
  end

  test "push rejects credentials, missing capability, and wrong ref scope", %{
    token: token,
    repo_id: repo_id
  } do
    credential =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "remoteUrl" => "https://token@example.invalid/repo.git",
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "dryRun" => true
      })
      |> json!(422)

    assert credential["error"]["code"] == "validation_error"

    limited_token =
      actor_token!("actor_push_limited", repo_id, ["repos:read"], ["refs/heads/main"])

    denied =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "dryRun" => true
      })
      |> json!(403)

    assert denied["error"]["code"] == "permission_denied"

    scoped_token =
      actor_token!("actor_push_scoped", repo_id, ["git:push"], ["refs/heads/release"])

    wrong_ref =
      build_conn()
      |> auth_conn(scoped_token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "dryRun" => true
      })
      |> json!(403)

    assert wrong_ref["error"]["code"] == "permission_denied"
  end

  test "mirror health and promotion dry-run are audited and protected", %{
    token: token,
    repo_id: repo_id
  } do
    mirror =
      create_mirror!(build_conn(), token, repo_id, %{
        "sourceNodeId" => "node_local",
        "targetNodeId" => "node_mirror",
        "status" => "synced",
        "behindBy" => 0
      })["mirror"]

    health =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/mirrors/#{mirror["id"]}/health", %{})
      |> json!(200)

    assert health["health"]["status"] == "healthy"

    promotion =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/mirrors/#{mirror["id"]}/promote", %{
        "dryRun" => true,
        "requireSynced" => true
      })
      |> json!(200)

    assert promotion["promotion"]["status"] == "planned"
    assert promotion["promotion"]["resultingPlacement"]["primaryNodeId"] == "node_mirror"
    assert_public_hygiene!(promotion)
  end

  defp actor_token!(actor_id, repo_id, caps, refs) do
    {:ok, _grant} =
      TreeDb.Capabilities.put_grant(%{
        "actorId" => actor_id,
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => caps,
        "refs" => refs,
        "paths" => ["**"]
      })

    dev_token!(build_conn(), %{"actorId" => actor_id, "tenantId" => "tenant_demo"})
  end

  defp git_bare!(repo_path, args) do
    {output, status} =
      System.cmd("git", ["--git-dir", repo_path | args], stderr_to_stdout: true)

    assert status == 0, output
    output
  end
end
