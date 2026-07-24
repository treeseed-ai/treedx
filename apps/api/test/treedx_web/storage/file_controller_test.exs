defmodule TreeDxWeb.FileControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    path = Path.join(TreeDx.Store.data_dir(), "repos/bare/file-api")
    create_git_fixture(path)

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "file-api", "localPath" => path})

    repo_id = json_response(conn, 200)["repo"]["repoId"]

    {:ok, token: token, repo_id: repo_id}
  end

  test "replays deterministic workspace creation without a duplicate writable lease", %{
    token: token,
    repo_id: repo_id
  } do
    request = %{
      "workspaceId" => "ws_assignment_replay_12345678",
      "baseRef" => "refs/heads/main",
      "branchName" => "refs/heads/agent/replay-safe",
      "mode" => "writable",
      "allowedPaths" => ["docs/**"],
      "ttlSeconds" => 1800
    }

    first =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/workspaces", request)
      |> json_response(200)

    replay =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/workspaces", request)
      |> json_response(200)

    assert first["workspaceId"] == request["workspaceId"]
    assert replay["workspaceId"] == first["workspaceId"]

    conflict =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/workspaces", %{request | "allowedPaths" => ["**"]})
      |> json_response(409)

    assert conflict["error"]["code"] == "conflict"
  end

  test "lists, reads, writes, patches, deletes, searches, diffs, and commits files", %{
    token: token,
    repo_id: repo_id
  } do
    workspace_id = create_workspace(token, repo_id, "refs/heads/agent/file-api", ["**"])

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/tree?path=")

    assert Enum.any?(json_response(conn, 200)["entries"], &(&1["path"] == "docs"))

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md")

    assert json_response(conn, 200)["content"] == "hello"

    conn =
      build_conn()
      |> auth(token)
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/new.md", %{
        "encoding" => "utf8",
        "content" => "TreeDX overlay content"
      })

    assert json_response(conn, 200)["file"]["source"] == "overlay"

    patch = """
    --- a/docs/readme.md
    +++ b/docs/readme.md
    @@ -1,1 +1,1 @@
    -hello
    +patched
    """

    conn =
      build_conn()
      |> auth(token)
      |> patch("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md", %{
        "patch" => patch
      })

    assert json_response(conn, 200)["file"]["sha"] =~ "blake3:"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/search", %{
        "query" => "overlay",
        "path" => "docs"
      })

    assert Enum.any?(json_response(conn, 200)["results"], &(&1["path"] == "docs/new.md"))

    conn =
      build_conn()
      |> auth(token)
      |> delete("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md", %{})

    assert json_response(conn, 200)["status"] == "deleted"

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md")

    assert json_response(conn, 404)["error"]["code"] == "not_found"

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/status")

    assert Enum.any?(json_response(conn, 200)["changes"], &(&1["path"] == "docs/new.md"))

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/diff")

    assert json_response(conn, 200)["diff"] =~ "diff --git a/docs/new.md b/docs/new.md"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/commit", %{
        "message" => "Commit overlay",
        "author" => %{"name" => "TreeDX Test", "email" => "test@example.invalid"}
      })

    committed = json_response(conn, 200)
    assert committed["status"] == "committed"
    assert committed["commitSha"] =~ ~r/^[0-9a-f]{40}$/

    read_workspace_id =
      create_workspace(token, repo_id, "refs/heads/agent/file-api-read", ["docs/**"], %{
        "baseRef" => "refs/heads/agent/file-api",
        "mode" => "read_only"
      })

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{read_workspace_id}/files?path=docs/new.md")

    assert json_response(conn, 200)["content"] == "TreeDX overlay content"
  end

  test "path traversal, protected paths, and missing token are rejected", %{
    token: token,
    repo_id: repo_id
  } do
    workspace_id = create_workspace(token, repo_id, "refs/heads/agent/policy", ["**"])

    conn =
      build_conn()
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md")

    assert json_response(conn, 401)["error"]["code"] == "authentication_required"

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=../secret")

    assert json_response(conn, 422)["error"]["code"] == "validation_error"

    conn =
      build_conn()
      |> auth(token)
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=.env", %{
        "encoding" => "utf8",
        "content" => "SECRET=true"
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"

    previous = System.get_env("TREEDX_MAX_FILE_BYTES")
    System.put_env("TREEDX_MAX_FILE_BYTES", "4")

    try do
      conn =
        build_conn()
        |> auth(token)
        |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/large.md", %{
          "encoding" => "utf8",
          "content" => "12345"
        })

      assert json_response(conn, 413)["error"]["code"] == "payload_too_large"
    after
      if previous,
        do: System.put_env("TREEDX_MAX_FILE_BYTES", previous),
        else: System.delete_env("TREEDX_MAX_FILE_BYTES")
    end
  end

  defp create_workspace(token, repo_id, branch_name, allowed_paths, overrides \\ %{}) do
    params =
      Map.merge(
        %{
          "baseRef" => "refs/heads/main",
          "branchName" => branch_name,
          "mode" => "writable",
          "allowedPaths" => allowed_paths,
          "ttlSeconds" => 1800
        },
        overrides
      )

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/workspaces", params)

    json_response(conn, 200)["workspaceId"]
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

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
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
