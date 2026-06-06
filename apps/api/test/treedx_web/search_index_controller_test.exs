defmodule TreeDxWeb.SearchIndexControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/search-index")
    create_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "search-index", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    {:ok, token: token, repo_id: repo_id}
  end

  test "refreshes, reports, and compacts search index metadata", %{token: token, repo_id: repo_id} do
    refresh =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/search/index/refresh", %{"paths" => ["docs/**"]})
      |> json_response(200)

    assert refresh["index"]["indexVersion"] =~ "sidx_"
    assert refresh["index"]["indexedPathCount"] == 2
    refute inspect(refresh) =~ "localPath"

    status =
      build_conn()
      |> auth(token)
      |> get("/api/v1/repos/#{repo_id}/search/index/status")
      |> json_response(200)

    assert status["index"]["ready"] == true
    assert status["index"]["segmentCount"] == 1

    compact =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/search/index/compact", %{"dryRun" => true})
      |> json_response(200)

    assert compact["compact"]["dryRun"] == true
    assert compact["compact"]["segmentsBefore"] == 1
  end

  test "search diagnostics are opt in and only include authorized result data", %{
    token: token,
    repo_id: repo_id
  } do
    without =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/search", %{
        "query" => "release",
        "paths" => ["docs/**"]
      })
      |> json_response(200)

    refute Map.has_key?(without, "diagnostics")

    with_diagnostics =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/search", %{
        "query" => "release",
        "paths" => ["docs/**"],
        "includeDiagnostics" => true,
        "diagnosticsLevel" => "ranking"
      })
      |> json_response(200)

    assert with_diagnostics["diagnostics"]["authorizedResultCount"] ==
             length(with_diagnostics["results"])

    assert with_diagnostics["diagnostics"]["returnedResultCount"] ==
             length(with_diagnostics["results"])

    refute inspect(with_diagnostics["diagnostics"]) =~ "secret"
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(Path.join(path, "docs"))
    File.mkdir_p!(Path.join(path, "secret"))
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(path, "docs/readme.md"), "# Readme\n\nRelease context.\n")
    File.write!(Path.join(path, "docs/guide.md"), "# Guide\n\nRelease guide.\n")
    File.write!(Path.join(path, "secret/hidden.md"), "# Hidden\n\nsecret release notes.\n")
    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
