defmodule TreeDxWeb.GraphControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/graph-api")
    create_graph_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "graph-api", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    {:ok, token: token, repo_id: repo_id, repo_path: repo_path}
  end

  test "requires bearer auth for graph endpoints", %{repo_id: repo_id} do
    conn = post(build_conn(), "/api/v1/repos/#{repo_id}/graph/refresh", %{})
    assert json_response(conn, 401)["error"]["code"] == "authentication_required"
  end

  test "refreshes, searches, reads, queries, relates, and builds subgraphs", %{
    token: token,
    repo_id: repo_id
  } do
    refresh =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
      |> json_response(200)

    assert refresh["ready"] == true
    assert refresh["snapshotRoot"] =~ "treedx://graph/#{repo_id}/"
    assert refresh["metrics"]["totalFiles"] == 2
    assert "docs/readme.md" in refresh["changed"]["added"]
    assert File.dir?(Path.join(TreeDx.Store.data_dir(), "graph/repos/#{repo_id}"))
    refute inspect(refresh) =~ "localPath"

    sections =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/search-sections", %{
        "query" => "release provenance",
        "limit" => 10
      })
      |> json_response(200)

    assert Enum.any?(sections["results"], &(&1["node"]["heading"] == "Overview"))

    files =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/search-files", %{"query" => "release"})
      |> json_response(200)

    file_node = hd(files["results"])["node"]
    assert file_node["nodeType"] == "File"

    entities =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/search-entities", %{"query" => "release"})
      |> json_response(200)

    assert Enum.any?(entities["results"], &(&1["node"]["nodeType"] == "Tag"))

    node =
      build_conn()
      |> auth(token)
      |> get("/api/v1/repos/#{repo_id}/graph/nodes/#{file_node["id"]}")
      |> json_response(200)

    assert node["node"]["id"] == file_node["id"]

    related =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/related", %{
        "nodeId" => file_node["id"],
        "relations" => ["references"],
        "options" => %{"depth" => 1, "limit" => 10}
      })
      |> json_response(200)

    assert Enum.any?(related["nodes"], &(&1["node"]["path"] == "docs/guide.md"))

    query =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/query", %{
        "query" => "release provenance",
        "scope" => "sections",
        "options" => %{"limit" => 8}
      })
      |> json_response(200)

    assert query["providerId"] == "treedx-graph-mvp"
    assert Enum.any?(query["nodes"], &(&1["node"]["nodeType"] == "Section"))

    subgraph =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/subgraph", %{
        "seedIds" => [file_node["id"]],
        "options" => %{"depth" => 1, "limit" => 10}
      })
      |> json_response(200)

    assert subgraph["seedId"] == file_node["id"]
    assert length(subgraph["nodes"]) > 0
  end

  test "protected paths are skipped by default", %{token: token, repo_id: repo_id} do
    refresh =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["**"]})
      |> json_response(200)

    assert refresh["metrics"]["totalFiles"] == 2

    search =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/graph/search-files", %{"query" => "secret"})
      |> json_response(200)

    assert search["results"] == []
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_graph_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.mkdir_p!(Path.join(path, "docs"))

    File.write!(Path.join(path, "docs/readme.md"), """
    ---
    title: Release Notes
    status: published
    tags:
      - release
    series: Handbook
    ---
    # Overview

    Release provenance links to [Guide](guide.md).
    """)

    File.write!(Path.join(path, "docs/guide.md"), """
    # Guide

    import Widget from './widget'

    Guide body for release work.
    """)

    File.write!(Path.join(path, ".env"), "SECRET=true\n")
    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
