defmodule TreeDbWeb.ExecControllerTest do
  use TreeDbWeb.ConnCase, async: false

  setup %{conn: conn} do
    token_conn = post(conn, "/api/v1/auth/dev-token", %{})
    token = json_response(token_conn, 200)["accessToken"]
    path = Path.join(TreeDb.Store.data_dir(), "repos/bare/exec-api")
    create_git_fixture(path)

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "exec-api", "localPath" => path})

    repo_id = json_response(conn, 200)["repo"]["repoId"]
    {:ok, token: token, repo_id: repo_id}
  end

  test "read-only command succeeds and output truncates", %{token: token, repo_id: repo_id} do
    workspace_id = create_workspace(token, repo_id, "refs/heads/agent/exec-read", ["docs/**"])

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "cat docs/readme.md",
        "mode" => "read_only"
      })

    response = json_response(conn, 200)
    assert response["exitCode"] == 0
    assert response["stdout"] == "hello"
    assert response["changedPaths"] == []

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "cat docs/long.txt",
        "mode" => "read_only",
        "maxOutputBytes" => 10
      })

    response = json_response(conn, 200)
    assert response["truncated"] == true
    assert byte_size(response["stdout"]) == 10
  end

  test "timeout kills command and disallowed commands are rejected", %{
    token: token,
    repo_id: repo_id
  } do
    workspace_id = create_workspace(token, repo_id, "refs/heads/agent/exec-policy", ["docs/**"])

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "sleep 2",
        "mode" => "write_limited",
        "timeoutMs" => 100
      })

    response = json_response(conn, 200)
    assert response["exitCode"] == 124
    assert response["stderr"] =~ "timed out"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "git push origin main",
        "mode" => "read_only"
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "cat ../secret",
        "mode" => "read_only"
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "echo changed > docs/nope.md",
        "mode" => "read_only"
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"
  end

  test "write-limited command captures changed paths and can be committed", %{
    token: token,
    repo_id: repo_id
  } do
    workspace_id = create_workspace(token, repo_id, "refs/heads/agent/exec-write", ["docs/**"])

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "printf shell-edit > docs/shell.md",
        "mode" => "write_limited"
      })

    response = json_response(conn, 200)
    assert response["exitCode"] == 0
    assert response["changedPaths"] == ["docs/shell.md"]

    conn =
      build_conn()
      |> auth(token)
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=docs/shell.md")

    assert json_response(conn, 200)["content"] == "shell-edit"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/commit", %{
        "message" => "Commit shell edit",
        "author" => %{"name" => "TreeDB Test", "email" => "test@example.invalid"}
      })

    assert json_response(conn, 200)["changedPaths"] == ["docs/shell.md"]
  end

  test "write-limited exec requires writable workspace capability", %{
    token: token,
    repo_id: repo_id
  } do
    workspace_id =
      create_workspace(token, repo_id, "refs/heads/agent/exec-read-only", ["docs/**"], %{
        "mode" => "read_only"
      })

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "printf nope > docs/nope.md",
        "mode" => "write_limited"
      })

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"
  end

  test "actor without live exec capability is rejected", %{repo_id: repo_id} do
    token =
      build_conn()
      |> post("/api/v1/auth/dev-token", %{
        "actorId" => "actor_no_exec",
        "tenantId" => "tenant_demo"
      })
      |> json_response(200)
      |> Map.fetch!("accessToken")

    {:ok, repo} = TreeDb.Store.get_repository(repo_id)
    {:ok, resolved} = TreeDb.Git.resolve_ref(repo["localPath"], "refs/heads/main")
    workspace_id = TreeDb.Ids.workspace()
    materialized_path = Path.join([TreeDb.Store.data_dir(), "workspaces", "active", workspace_id])
    File.mkdir_p!(materialized_path)

    {:ok, _workspace} =
      TreeDb.Store.put_workspace(%{
        id: workspace_id,
        repositoryId: repo_id,
        nodeId: "node_local",
        actorId: "actor_no_exec",
        tenantId: "tenant_demo",
        baseRef: "refs/heads/main",
        baseCommitSha: resolved["target"],
        branchName: nil,
        mode: "read_only",
        allowedPaths: ["docs/**"],
        capabilities: ["workspace:exec:read_only"],
        ttlSeconds: 1800,
        materializedPath: materialized_path,
        effectiveScope: %{
          actorId: "actor_no_exec",
          tenantId: "tenant_demo",
          repoIds: [repo_id],
          capabilities: ["workspace:exec:read_only"],
          refs: ["refs/heads/main"],
          paths: ["docs/**"]
        }
      })

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "cat docs/readme.md",
        "mode" => "read_only"
      })

    assert json_response(conn, 409)["error"]["code"] == "workspace_revoked"
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
    git(path, ["config", "user.name", "TreeDB Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.mkdir_p!(Path.join(path, "docs"))
    File.write!(Path.join(path, "docs/readme.md"), "hello")
    File.write!(Path.join(path, "docs/long.txt"), String.duplicate("x", 100))
    git(path, ["add", "docs/readme.md", "docs/long.txt"])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
