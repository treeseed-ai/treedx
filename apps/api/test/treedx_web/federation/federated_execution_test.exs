defmodule TreeDxWeb.FederatedExecutionTest do
  use TreeDxWeb.ConnCase, async: false

  test "global search merges authorized local repository results", %{conn: conn} do
    token = dev_token!(conn)
    {repo_a, repo_b} = create_two_repos!(token)

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [repo_a["repoId"], repo_b["repoId"]],
        "refs" => %{
          repo_a["repoId"] => "refs/heads/main",
          repo_b["repoId"] => "refs/heads/main"
        },
        "paths" => %{
          repo_a["repoId"] => ["docs/**"],
          repo_b["repoId"] => ["docs/**"]
        },
        "query" => "mvp provenance",
        "limit" => 20,
        "includeErrors" => true
      })
      |> json!(200)

    assert %{"results" => results, "diagnostics" => diagnostics} = body["search"]

    assert Enum.any?(
             results,
             &(&1["repoId"] == repo_a["repoId"] and &1["path"] == "docs/readme.md")
           )

    assert Enum.any?(
             results,
             &(&1["repoId"] == repo_b["repoId"] and &1["path"] == "docs/readme.md")
           )

    assert diagnostics["executedRepoCount"] == 2
    assert diagnostics["partialFailureCount"] == 0
    assert_public_hygiene!(body)
  end

  test "global query supports text, path, and combined queries", %{conn: conn} do
    token = dev_token!(conn)
    {repo_a, repo_b} = create_two_repos!(token)

    for type <- ["text", "path", "combined"] do
      body =
        build_conn()
        |> auth_conn(token)
        |> post("/api/v1/query", %{
          "repoIds" => [repo_a["repoId"], repo_b["repoId"]],
          "refs" => %{
            repo_a["repoId"] => "refs/heads/main",
            repo_b["repoId"] => "refs/heads/main"
          },
          "paths" => %{repo_a["repoId"] => ["docs/**"], repo_b["repoId"] => ["docs/**"]},
          "type" => type,
          "query" => if(type == "path", do: "readme", else: "mvp provenance"),
          "includeErrors" => true
        })
        |> json!(200)

      assert body["query"]["type"] == type
      assert is_list(body["query"]["results"])
      assert body["query"]["diagnostics"]["executedRepoCount"] == 2
      assert_public_hygiene!(body)
    end
  end

  test "global context merges local packs with a global budget", %{conn: conn} do
    token = dev_token!(conn)
    {repo_a, repo_b} = create_two_repos!(token)
    refresh_graph!(token, repo_a["repoId"])
    refresh_graph!(token, repo_b["repoId"])

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/context/build", %{
        "repoIds" => [repo_a["repoId"], repo_b["repoId"]],
        "refs" => %{repo_a["repoId"] => "refs/heads/main", repo_b["repoId"] => "refs/heads/main"},
        "paths" => %{repo_a["repoId"] => ["docs/**"], repo_b["repoId"] => ["docs/**"]},
        "query" => "mvp provenance",
        "budget" => %{"maxNodes" => 2},
        "includeErrors" => true
      })
      |> json!(200)

    assert length(body["context"]["nodes"]) <= 2
    assert body["context"]["diagnostics"]["executedRepoCount"] == 2
    assert_public_hygiene!(body)
  end

  defp create_two_repos!(token) do
    data_dir = TreeDx.Store.data_dir()
    repo_a_path = Path.join(data_dir, "repos/bare/federated-a")
    repo_b_path = Path.join(data_dir, "repos/bare/federated-b")
    create_git_repo!(repo_a_path, message: "Federated A")
    create_git_repo!(repo_b_path, message: "Federated B")

    repo_a =
      register_repo!(build_conn(), token, %{
        "name" => "federated-a",
        "localPath" => repo_a_path
      })["repo"]

    repo_b =
      register_repo!(build_conn(), token, %{
        "name" => "federated-b",
        "localPath" => repo_b_path
      })["repo"]

    {repo_a, repo_b}
  end

  defp refresh_graph!(token, repo_id) do
    build_conn()
    |> auth_conn(token)
    |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
    |> json!(200)
  end
end
