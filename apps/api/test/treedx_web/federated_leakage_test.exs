defmodule TreeDxWeb.FederatedLeakageTest do
  use TreeDxWeb.ConnCase, async: false

  test "global search does not expose hidden repository content", %{conn: conn} do
    admin_token = dev_token!(conn)
    data_dir = TreeDx.Store.data_dir()
    visible_path = Path.join(data_dir, "repos/bare/federated-visible")
    hidden_path = Path.join(data_dir, "repos/bare/federated-hidden")
    create_git_repo!(visible_path)
    create_git_repo!(hidden_path, message: "Hidden federated fixture")

    visible =
      register_repo!(build_conn(), admin_token, %{
        "name" => "federated-visible",
        "localPath" => visible_path
      })["repo"]

    hidden =
      register_repo!(build_conn(), admin_token, %{
        "name" => "federated-hidden-secret",
        "localPath" => hidden_path
      })["repo"]

    {:ok, _grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "actor_federated_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [visible["repoId"]],
        "capabilities" => ["query:federated", "files:search", "files:read"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/readme.md"]
      })

    token =
      dev_token!(build_conn(), %{
        "actorId" => "actor_federated_limited",
        "tenantId" => "tenant_demo"
      })

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [visible["repoId"], hidden["repoId"]],
        "refs" => %{visible["repoId"] => "refs/heads/main", hidden["repoId"] => "refs/heads/main"},
        "paths" => %{
          visible["repoId"] => ["docs/readme.md"],
          hidden["repoId"] => ["docs/private/**"]
        },
        "query" => "Hidden",
        "includeErrors" => true
      })
      |> json!(200)

    json = Jason.encode!(body)
    assert body["search"]["diagnostics"]["executedRepoCount"] == 1
    assert body["search"]["diagnostics"]["rejectedRepoCount"] == 1
    refute json =~ hidden["name"]
    refute json =~ "docs/private/hidden.md"
    refute json =~ "Hidden federated fixture"
    refute_hidden_leakage_markers!(body)
    assert_public_hygiene!(body)
  end

  test "empty effective scope returns federated_scope_empty without hidden snippets", %{
    conn: conn
  } do
    admin_token = dev_token!(conn)
    data_dir = TreeDx.Store.data_dir()
    hidden_path = Path.join(data_dir, "repos/bare/federated-denied")
    create_git_repo!(hidden_path)

    hidden =
      register_repo!(build_conn(), admin_token, %{
        "name" => "federated-denied-secret",
        "localPath" => hidden_path
      })["repo"]

    {:ok, _grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "actor_no_federated_scope",
        "tenantId" => "tenant_demo",
        "repoIds" => ["repo_other"],
        "capabilities" => ["query:federated", "files:search"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      })

    token =
      dev_token!(build_conn(), %{
        "actorId" => "actor_no_federated_scope",
        "tenantId" => "tenant_demo"
      })

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/query", %{
        "repoIds" => [hidden["repoId"]],
        "refs" => %{hidden["repoId"] => "refs/heads/main"},
        "paths" => %{hidden["repoId"] => ["docs/**"]},
        "type" => "text",
        "query" => "mvp provenance"
      })
      |> json!(403)

    assert body["error"]["code"] == "federated_scope_empty"
    refute Jason.encode!(body) =~ "mvp provenance"
    assert_public_hygiene!(body)
  end
end
