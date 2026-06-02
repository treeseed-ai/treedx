defmodule TreeDbWeb.ContextControllerTest do
  use TreeDbWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDb.Store.data_dir(), "repos/bare/context-api")
    create_context_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "context-api", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    build_conn()
    |> auth(token)
    |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
    |> json_response(200)

    {:ok, token: token, repo_id: repo_id}
  end

  test "builds a token-budgeted context pack", %{token: token, repo_id: repo_id} do
    context =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/context/build", %{
        "query" => "release provenance",
        "scope" => "sections",
        "budget" => %{"maxNodes" => 2, "maxTokens" => 80, "includeMode" => "mixed"},
        "options" => %{"depth" => 1, "limit" => 8}
      })
      |> json_response(200)

    assert context["repoId"] == repo_id
    assert length(context["nodes"]) <= 2
    assert context["totalTokenEstimate"] <= 80
    assert Enum.any?(context["includedPaths"], &(&1 == "docs/readme.md"))
    assert context["diagnostics"]["effectiveScope"]["repoId"] == repo_id
  end

  test "parses ctx DSL and reports parse errors as results", %{token: token, repo_id: repo_id} do
    parsed =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/context/parse-ctx", %{
        "source" =>
          "ctx \"release provenance\" for research in /docs via references depth 1 limit 8 budget 1200 as brief"
      })
      |> json_response(200)

    assert parsed["query"]["stage"] == "research"
    assert parsed["query"]["budget"]["maxTokens"] == 1200
    assert parsed["errors"] == []

    invalid =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/context/parse-ctx", %{"source" => "search release"})
      |> json_response(200)

    assert invalid["query"] == nil
    assert invalid["errors"] != []
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_context_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDB Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.mkdir_p!(Path.join(path, "docs"))

    File.write!(Path.join(path, "docs/readme.md"), """
    ---
    title: Release Context
    tags: release
    ---
    # Overview

    Release provenance summary for context packing.
    """)

    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
