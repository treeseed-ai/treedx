defmodule TreeDxWeb.RepoControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    {:ok, token: token}
  end

  test "register rejects missing token", %{conn: conn} do
    conn =
      post(conn, "/api/v1/repos/register", %{
        "name" => "demo",
        "localPath" => Path.join(TreeDx.Store.data_dir(), "repos/bare/demo.git")
      })

    assert json_response(conn, 401)["error"]["code"] == "authentication_required"
  end

  test "registers, lists, and returns status", %{token: token} do
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/controller-demo")
    create_git_fixture(path)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{"name" => "controller-demo", "localPath" => path})

    repo_id = json_response(conn, 200)["repo"]["repoId"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/repos")

    assert Enum.any?(json_response(conn, 200)["repos"], &(&1["repoId"] == repo_id))

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/repos/#{repo_id}/status")

    assert json_response(conn, 200)["git"]["exists"] == true
  end

  test "retires a managed virtual knowledge repository idempotently", %{token: token} do
    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos", %{"repositoryName" => "retirement-fixture"})

    repo_id = json_response(created, 200)["repo"]["repoId"]

    retired =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete("/api/v1/repos/#{repo_id}")

    assert json_response(retired, 200)["alreadyRetired"] == false

    missing =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/repos/#{repo_id}")

    assert json_response(missing, 404)["error"]["code"] == "not_found"

    replay =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete("/api/v1/repos/#{repo_id}")

    assert json_response(replay, 200)["alreadyRetired"] == true
  end

  test "lists refs and remotes, syncs, and manages workspace lifecycle", %{token: token} do
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/git-fixture")
    create_git_fixture(path)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{"name" => "git-fixture", "localPath" => path})

    repo_id = json_response(conn, 200)["repo"]["repoId"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/repos/#{repo_id}/refs")

    assert Enum.any?(json_response(conn, 200)["refs"], &(&1["name"] == "refs/heads/main"))

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/repos/#{repo_id}/remotes")

    assert Enum.any?(json_response(conn, 200)["remotes"], &(&1["name"] == "origin"))

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/sync", %{})

    assert json_response(conn, 200)["refreshed"] == false

    workspace_params = %{
      "baseRef" => "refs/heads/main",
      "branchName" => "refs/heads/agent/demo",
      "mode" => "writable",
      "allowedPaths" => ["docs/**"],
      "ttlSeconds" => 1800
    }

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/workspaces", workspace_params)

    workspace = json_response(conn, 200)
    workspace_id = workspace["workspaceId"]
    assert workspace["status"] == "ready"
    assert workspace["allowedPaths"] == ["docs/**"]
    assert workspace["effectiveScope"]["refs"] == ["refs/heads/agent/demo"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/workspaces", %{
        workspace_params
        | "branchName" => "agent/plain-demo"
      })

    plain_workspace = json_response(conn, 200)
    assert plain_workspace["branchName"] == "refs/heads/agent/plain-demo"
    assert plain_workspace["effectiveScope"]["refs"] == ["refs/heads/agent/plain-demo"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/workspaces", workspace_params)

    assert json_response(conn, 409)["error"]["code"] == "conflict"

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/workspaces/#{workspace_id}")

    assert json_response(conn, 200)["workspaceId"] == workspace_id

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/workspaces/#{workspace_id}/close", %{})

    assert json_response(conn, 200)["status"] == "closed"
  end

  test "workspace creation rejects refs outside effective scope", %{token: token} do
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/scope-fixture")
    create_git_fixture(path)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{"name" => "scope-fixture", "localPath" => path})

    repo_id = json_response(conn, 200)["repo"]["repoId"]

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/workspaces", %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/tags/nope",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"
  end

  test "abandons only the exact committed branch owned by a workspace", %{token: token} do
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/workspace-abandonment")
    create_git_fixture(path)

    registered =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{"name" => "workspace-abandonment", "localPath" => path})

    repo_id = json_response(registered, 200)["repo"]["repoId"]

    created =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/workspaces", %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/knowledge/abandoned",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    workspace_id = json_response(created, 200)["workspaceId"]

    written =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/abandoned.md", %{
        "encoding" => "utf8",
        "content" => "not published"
      })

    assert json_response(written, 200)["file"]["source"] == "overlay"

    committed =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/workspaces/#{workspace_id}/commit", %{
        "message" => "unpublished knowledge",
        "author" => %{"name" => "TreeDX Test", "email" => "test@example.invalid"}
      })

    commit_sha = json_response(committed, 200)["commitSha"]

    moved =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/workspaces/#{workspace_id}/abandon", %{
        "expectedHead" => String.duplicate("0", 40)
      })

    assert json_response(moved, 409)["error"]["code"] == "conflict"

    abandoned =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/workspaces/#{workspace_id}/abandon", %{"expectedHead" => commit_sha})

    payload = json_response(abandoned, 200)
    assert payload["workspace"]["status"] == "closed"
    assert payload["discardedRef"]["status"] == "discarded"

    assert elem(
             System.cmd(
               "git",
               ["show-ref", "--quiet", "--verify", "refs/heads/knowledge/abandoned"],
               cd: path,
               stderr_to_stdout: true
             ),
             1
           ) != 0

    replay =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/workspaces/#{workspace_id}/abandon", %{"expectedHead" => commit_sha})

    assert json_response(replay, 200)["discardedRef"]["status"] == "already_discarded"
  end

  test "atomically promotes a reviewed managed branch by exact base", %{token: token} do
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/ref-promotion")
    create_git_fixture(path)
    main_sha = git_output(path, ["rev-parse", "refs/heads/main"])
    git(path, ["checkout", "-b", "knowledge/reviewed"])
    File.write!(Path.join(path, "docs/reviewed.md"), "reviewed")
    git(path, ["add", "docs/reviewed.md"])
    git(path, ["commit", "-m", "reviewed knowledge"])
    reviewed_sha = git_output(path, ["rev-parse", "refs/heads/knowledge/reviewed"])

    registered =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/register", %{"name" => "ref-promotion", "localPath" => path})

    repo_id = json_response(registered, 200)["repo"]["repoId"]

    promoted =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/refs/promote", %{
        "sourceRef" => "refs/heads/knowledge/reviewed",
        "destinationRef" => "refs/heads/main",
        "expectedDestinationHead" => main_sha
      })

    assert json_response(promoted, 200)["promotion"]["afterHead"] == reviewed_sha
    assert git_output(path, ["rev-parse", "refs/heads/main"]) == reviewed_sha

    replay =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/refs/promote", %{
        "sourceRef" => "refs/heads/knowledge/reviewed",
        "destinationRef" => "refs/heads/main",
        "expectedDestinationHead" => main_sha
      })

    assert json_response(replay, 200)["promotion"]["status"] == "already_current"

    retired =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/refs/retire", %{
        "ref" => "refs/heads/knowledge/reviewed",
        "mergedIntoRef" => "refs/heads/main",
        "expectedHead" => reviewed_sha,
        "expectedMergedIntoHead" => reviewed_sha
      })

    assert json_response(retired, 200)["retirement"]["status"] == "retired"

    retired_again =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> post("/api/v1/repos/#{repo_id}/refs/retire", %{
        "ref" => "refs/heads/knowledge/reviewed",
        "mergedIntoRef" => "refs/heads/main",
        "expectedHead" => reviewed_sha,
        "expectedMergedIntoHead" => reviewed_sha
      })

    assert json_response(retired_again, 200)["retirement"]["status"] == "already_retired"
  end

  defp create_git_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.mkdir_p!(Path.join(path, "docs"))
    File.write!(Path.join(path, "docs/readme.md"), "hello")
    git(path, ["add", "docs/readme.md"])
    git(path, ["commit", "-m", "init"])
    git(path, ["remote", "add", "origin", "https://example.invalid/demo.git"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end

  defp git_output(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
    String.trim(output)
  end
end
