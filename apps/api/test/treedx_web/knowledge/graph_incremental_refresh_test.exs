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
    assert second["loadedPathCount"] == 1
    assert second["reusedPathCount"] == 1
    assert second["indexedPathCount"] == 1
    assert second["changed"]["modified"] == ["docs/readme.md"]
    assert second["jobId"] =~ "grjob_"

    status =
      build_conn()
      |> auth(token)
      |> get("/api/v1/repos/#{repo_id}/graph/refresh-jobs/#{second["jobId"]}")
      |> json_response(200)

    assert status["job"]["status"] == "completed"
    assert status["job"]["graphVersion"] == second["graphVersion"]
    refute inspect(status) =~ TreeDx.Store.data_dir()

    File.rm!(Path.join(repo_path, "docs/guide.md"))
    git(repo_path, ["add", "."])
    git(repo_path, ["commit", "-m", "remove guide"])

    removed =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{
        "paths" => ["docs/**"],
        "incremental" => true,
        "baseGraphVersion" => second["graphVersion"],
        "changedPaths" => ["docs/guide.md"]
      })
      |> json_response(200)

    assert removed["refreshMode"] == "incremental"
    assert removed["loadedPathCount"] == 0
    assert removed["reusedPathCount"] == 1
    assert removed["removedPathCount"] == 1
    assert removed["changed"]["removed"] == ["docs/guide.md"]
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

  test "job reader authorizes its stored ref rather than a caller ref or repository default", %{
    repo_id: repo_id
  } do
    {:ok, _} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "graph_job_unit_reader",
        "tenantId" => "tenant_demo",
        "repoIds" => ["*"],
        "refs" => ["*"],
        "paths" => ["docs/**"],
        "capabilities" => ["graph:query"]
      })

    {:ok, job} =
      TreeDx.Graph.RefreshJobs.start(
        %{repo: %{"id" => repo_id}, ref: "refs/heads/staging"},
        %{"paths" => ["docs/**"]},
        "full",
        nil,
        false
      )

    {:ok, completed} = TreeDx.Graph.RefreshJobs.complete(job, "graph_staging", 2, 0)

    principal = fn ref ->
      %{
        "actorId" => "graph_job_unit_reader",
        "authMode" => "connected",
        "tokenScope" => %{
          "repoIds" => [repo_id],
          "capabilities" => ["graph:query"],
          "refs" => [ref],
          "paths" => ["docs/**"]
        }
      }
    end

    staging = principal.("refs/heads/staging")
    main = principal.("refs/heads/main")

    observations =
      for params <- [%{}, %{"ref" => "refs/heads/main"}, %{"ref" => "refs/heads/staging"}] do
        {TreeDx.Graph.RefreshJobs.get(repo_id, job["jobId"], params, staging),
         TreeDx.Graph.RefreshJobs.get(repo_id, job["jobId"], params, main)}
      end

    missing = TreeDx.Graph.RefreshJobs.get(repo_id, "grjob_missing", %{}, staging)
    foreign = TreeDx.Graph.RefreshJobs.get("repo_missing", job["jobId"], %{}, staging)
    {:ok, after_reads} = TreeDx.Store.get_graph_refresh_job(repo_id, job["jobId"])
    assert after_reads == completed

    for {allowed, denied} <- observations do
      assert {:ok, %{job: public}} = allowed
      assert public == TreeDx.Graph.RefreshJobs.public(completed)
      assert {:error, %{code: "permission_denied"}} = denied
    end

    assert {:error, %{code: "not_found"}} = missing
    assert {:error, %{code: "not_found"}} = foreign

    assert {:error, %{code: "authentication_required"}} =
             TreeDx.Graph.RefreshJobs.get(repo_id, job["jobId"], %{}, nil)
  end

  test "native graph job HTTP readback admits only the job ref and retains completed history", %{
    token: token,
    repo_id: repo_id,
    repo_path: repo_path
  } do
    git(repo_path, ["branch", "staging"])

    refresh =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{
        "ref" => "refs/heads/staging",
        "paths" => ["docs/**"]
      })
      |> json_response(200)

    {:ok, original} = TreeDx.Store.get_graph_refresh_job(repo_id, refresh["jobId"])

    tokens =
      for {actor, ref} <- [
            {"graph_staging_reader", "refs/heads/staging"},
            {"graph_main_reader", "refs/heads/main"}
          ] do
        {:ok, _} =
          TreeDx.Capabilities.put_grant(%{
            "actorId" => actor,
            "tenantId" => "tenant_demo",
            "repoIds" => [repo_id],
            "refs" => [ref],
            "paths" => ["docs/**"],
            "capabilities" => ["graph:query"]
          })

        build_conn()
        |> post("/api/v1/auth/dev-token", %{"actorId" => actor, "tenantId" => "tenant_demo"})
        |> json_response(200)
        |> Map.fetch!("accessToken")
      end

    [staging_token, main_token] = tokens
    path = "/api/v1/repos/#{repo_id}/graph/refresh-jobs/#{refresh["jobId"]}"

    observations =
      for suffix <- ["", "?ref=refs%2Fheads%2Fmain", "?ref=refs%2Fheads%2Fstaging"] do
        {build_conn() |> auth(staging_token) |> get(path <> suffix),
         build_conn() |> auth(main_token) |> get(path <> suffix)}
      end

    missing =
      build_conn()
      |> auth(staging_token)
      |> get("/api/v1/repos/#{repo_id}/graph/refresh-jobs/grjob_missing")

    {:ok, after_reads} = TreeDx.Store.get_graph_refresh_job(repo_id, refresh["jobId"])
    assert after_reads == original

    for {allowed, denied} <- observations do
      public = json_response(allowed, 200)["job"]
      assert public["ref"] == "refs/heads/staging"
      assert public["status"] == "completed"
      assert public["graphVersion"] == refresh["graphVersion"]
      assert json_response(denied, 403)["error"]["code"] == "permission_denied"
    end

    assert json_response(missing, 404)["error"]["code"] == "not_found"

    assert json_response(get(build_conn(), path), 401)["error"]["code"] ==
             "authentication_required"
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
