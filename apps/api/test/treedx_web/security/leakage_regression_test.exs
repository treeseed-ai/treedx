defmodule TreeDxWeb.LeakageRegressionTest do
  use TreeDxWeb.ConnCase, async: false

  test "federation planning does not expose hidden repository content", %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
    repo_a_path = Path.join(data_dir, "repos/bare/leakage-repo-a")
    repo_b_path = Path.join(data_dir, "repos/bare/leakage-repo-b")
    create_git_repo!(repo_a_path)
    create_git_repo!(repo_b_path, message: "Hidden fixture")

    admin_token = dev_token!(conn)

    repo_a =
      register_repo!(build_conn(), admin_token, %{
        "name" => "leakage-repo-a",
        "localPath" => repo_a_path
      })["repo"]

    repo_b =
      register_repo!(build_conn(), admin_token, %{
        "name" => "leakage-repo-b",
        "localPath" => repo_b_path
      })["repo"]

    {:ok, _placement} =
      TreeDx.Store.put_repository_placement(%{
        repositoryId: repo_a["repoId"],
        primaryNodeId: "node_local",
        mirrorNodeIds: [],
        readPolicy: "primary_or_mirror",
        writePolicy: "primary_only",
        migrationState: "stable"
      })

    {:ok, _grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "actor_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_a["repoId"]],
        "capabilities" => ["files:search", "query:federated"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      })

    limited_token =
      dev_token!(build_conn(), %{"actorId" => "actor_limited", "tenantId" => "tenant_demo"})

    plan =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/federation/query/plan", %{
        "repoIds" => [repo_a["repoId"], repo_b["repoId"]],
        "refs" => %{repo_a["repoId"] => "refs/heads/main", repo_b["repoId"] => "refs/heads/main"},
        "paths" => %{repo_a["repoId"] => ["docs/**"], repo_b["repoId"] => ["secret/**"]},
        "capabilities" => ["files:search"]
      })
      |> json!(200)

    json = Jason.encode!(plan)
    assert [%{"repoId" => repo_a_id}] = plan["effectiveScope"]["repos"]
    assert repo_a_id == repo_a["repoId"]
    refute json =~ "mvp provenance"
    refute json =~ "docs/private/hidden.md"
    refute json =~ repo_b["name"]
    refute_hidden_leakage_markers!(plan)
  end
end
