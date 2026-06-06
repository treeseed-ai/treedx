defmodule TreeDxWeb.PublicHygieneTest do
  use TreeDxWeb.ConnCase, async: false

  test "representative public API responses do not leak internal paths or secrets", %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/public-hygiene-repo")
    create_git_repo!(repo_path)
    token = dev_token!(conn)

    repo_response =
      register_repo!(build_conn(), token, %{
        "name" => "public-hygiene-repo",
        "localPath" => repo_path
      })

    repo_id = repo_response["repo"]["repoId"]

    responses = [
      repo_response,
      build_conn() |> auth_conn(token) |> get("/api/v1/repos/#{repo_id}") |> json!(200),
      build_conn() |> auth_conn(token) |> get("/api/v1/repos/#{repo_id}/status") |> json!(200)
    ]

    workspace =
      create_workspace!(build_conn(), token, repo_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/hygiene",
        "mode" => "writable",
        "allowedPaths" => ["docs/**", "plain/**", "package.json"]
      })

    workspace_id = workspace["workspaceId"]

    write =
      build_conn()
      |> auth_conn(token)
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md", %{
        "content" => "# Public Hygiene\n\nmvp provenance\n"
      })
      |> json!(200)

    search =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/search", %{"query" => "mvp provenance"})
      |> json!(200)

    query =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/query", %{
        "ref" => "refs/heads/main",
        "paths" => ["docs/**"],
        "query" => "mvp provenance"
      })
      |> json!(200)

    graph_refresh =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{
        "ref" => "refs/heads/main",
        "paths" => ["docs/**", "plain/**"]
      })
      |> json!(200)

    context =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/context/build", %{
        "ref" => "refs/heads/main",
        "query" => "mvp provenance",
        "scope" => "sections"
      })
      |> json!(200)

    snapshot =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/snapshots/build", %{
        "ref" => "refs/heads/main",
        "kind" => "repository_snapshot",
        "paths" => ["docs/**"]
      })
      |> json!(200)

    artifact =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/artifacts/export", %{
        "snapshotId" => snapshot["snapshot"]["snapshotId"]
      })
      |> json!(200)

    mirror =
      create_mirror!(build_conn(), token, repo_id, %{
        "targetNodeId" => "node_local",
        "status" => "pending"
      })

    migration =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/migrations", %{
        "targetNodeId" => "node_local",
        "dryRun" => true,
        "requireMirrorSynced" => false
      })
      |> json!(200)

    audit =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/audit/events", %{"repoId" => repo_id, "limit" => 50})
      |> json!(200)

    [
      workspace,
      write,
      search,
      query,
      graph_refresh,
      context,
      snapshot,
      artifact,
      mirror,
      migration,
      audit
      | responses
    ]
    |> Enum.each(&assert_public_hygiene!/1)
  end
end
