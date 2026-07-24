defmodule TreeDxWeb.FederatedGraphTest do
  use TreeDxWeb.ConnCase, async: false

  test "global graph query qualifies graph node identifiers", %{conn: conn} do
    token = dev_token!(conn)
    data_dir = TreeDx.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/federated-graph")
    create_git_repo!(repo_path)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "federated-graph",
        "localPath" => repo_path
      })["repo"]

    build_conn()
    |> auth_conn(token)
    |> post("/api/v1/repos/#{repo["repoId"]}/graph/refresh", %{"paths" => ["docs/**"]})
    |> json!(200)

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/graph/query", %{
        "repoIds" => [repo["repoId"]],
        "refs" => %{repo["repoId"] => "refs/heads/main"},
        "paths" => %{repo["repoId"] => ["docs/**"]},
        "query" => "mvp provenance",
        "options" => %{"limit" => 10, "maxNodes" => 10},
        "includeErrors" => true
      })
      |> json!(200)

    assert [%{"id" => "treedx://repo/" <> _} | _] = body["graph"]["nodes"]
    assert Enum.all?(body["graph"]["nodes"], &(&1["repoId"] == repo["repoId"]))
    assert is_integer(body["graph"]["diagnostics"]["crossRepoEdgeCount"])
    assert_public_hygiene!(body)
  end
end
