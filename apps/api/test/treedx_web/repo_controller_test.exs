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
end
