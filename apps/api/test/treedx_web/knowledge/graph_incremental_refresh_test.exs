defmodule TreeDxWeb.GraphIncrementalRefreshTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/graph-incremental")
    create_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "graph-incremental", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    {:ok, token: token, repo_id: repo_id, repo_path: repo_path}
  end

  test "records incremental graph refresh job metadata and exposes status", %{
    token: token,
    repo_id: repo_id,
    repo_path: repo_path
  } do
    first =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
      |> json_response(200)

    File.write!(Path.join(repo_path, "docs/readme.md"), "# Readme\n\nUpdated release context.\n")
    git(repo_path, ["add", "."])
    git(repo_path, ["commit", "-m", "update readme"])

    second =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{
        "paths" => ["docs/**"],
        "incremental" => true,
        "baseGraphVersion" => first["graphVersion"],
        "changedPaths" => ["docs/readme.md"]
      })
      |> json_response(200)

    assert second["refreshMode"] == "incremental"
    assert second["fallbackReason"] == nil
    assert second["changedPathCount"] == 1
    assert second["indexedPathCount"] == 1
    assert second["jobId"] =~ "grjob_"

    status =
      build_conn()
      |> auth(token)
      |> get("/api/v1/repos/#{repo_id}/graph/refresh-jobs/#{second["jobId"]}")
      |> json_response(200)

    assert status["job"]["status"] == "completed"
    assert status["job"]["graphVersion"] == second["graphVersion"]
    refute inspect(status) =~ TreeDx.Store.data_dir()
  end

  test "falls back to full refresh for stale base graph", %{token: token, repo_id: repo_id} do
    build_conn()
    |> auth(token)
    |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
    |> json_response(200)

    refresh =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{
        "paths" => ["docs/**"],
        "incremental" => true,
        "baseGraphVersion" => "graph_missing",
        "changedPaths" => ["docs/readme.md"]
      })
      |> json_response(200)

    assert refresh["refreshMode"] == "full"
    assert refresh["fallbackReason"] == "stale_base_graph"
    assert refresh["stale"] == true
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(Path.join(path, "docs"))
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(path, "docs/readme.md"), "# Readme\n\nRelease context.\n")
    File.write!(Path.join(path, "docs/guide.md"), "# Guide\n\nRelease guide.\n")
    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
