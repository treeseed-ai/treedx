defmodule TreeDbFederationRemoteFake do
  def execute(operation, allowed, params, auth_header) do
    send(Application.fetch_env!(:treedb, :federation_test_pid), {
      :remote_execute,
      operation,
      allowed,
      params,
      auth_header
    })

    case Application.fetch_env!(:treedb, :federation_test_result) do
      {:ok, payload} -> {:ok, payload}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule TreeDbWeb.FederatedRemoteRoutingTest do
  use TreeDbWeb.ConnCase, async: false

  setup do
    Application.put_env(:treedb, :federation_remote_node, TreeDbFederationRemoteFake)
    Application.put_env(:treedb, :federation_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:treedb, :federation_remote_node)
      Application.delete_env(:treedb, :federation_test_pid)
      Application.delete_env(:treedb, :federation_test_result)
    end)
  end

  test "remote HTTP execution receives reduced path scope and forwarded auth", %{conn: conn} do
    token = dev_token!(conn)
    repo = remote_repo!(token, "node_remote")

    Application.put_env(:treedb, :federation_test_result, {
      :ok,
      %{
        "results" => [
          %{"path" => "docs/readme.md", "score" => 3, "snippet" => "remote authorized"}
        ],
        "page" => %{"limit" => 20, "hasMore" => false}
      }
    })

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [repo["repoId"]],
        "refs" => %{repo["repoId"] => "refs/heads/main"},
        "paths" => %{repo["repoId"] => ["docs/**"]},
        "query" => "remote",
        "includeErrors" => true
      })
      |> json!(200)

    assert_receive {:remote_execute, :search, allowed, params, auth_header}
    assert allowed.paths == ["docs/**"]
    assert params["paths"][repo["repoId"]] == ["docs/**"]
    assert auth_header =~ "Bearer "
    assert [%{"repoId" => repo_id, "source" => "remote"}] = body["search"]["results"]
    assert repo_id == repo["repoId"]
  end

  test "remote partial failure is returned when includeErrors is true", %{conn: conn} do
    token = dev_token!(conn)
    repo = remote_repo!(token, "node_remote")

    Application.put_env(:treedb, :federation_test_result, {
      :error,
      %{
        repoId: repo["repoId"],
        nodeId: "node_remote",
        code: "federated_node_timeout",
        message: "Federated node timed out.",
        source: "remote"
      }
    })

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [repo["repoId"]],
        "refs" => %{repo["repoId"] => "refs/heads/main"},
        "paths" => %{repo["repoId"] => ["docs/**"]},
        "query" => "remote",
        "includeErrors" => true
      })
      |> json!(200)

    assert body["search"]["errors"] == [
             %{
               "repoId" => repo["repoId"],
               "nodeId" => "node_remote",
               "code" => "federated_node_timeout",
               "message" => "Federated node timed out."
             }
           ]
  end

  test "remote partial failure fails the request without includeErrors", %{conn: conn} do
    token = dev_token!(conn)
    repo = remote_repo!(token, "node_remote")

    Application.put_env(:treedb, :federation_test_result, {
      :error,
      %{
        repoId: repo["repoId"],
        nodeId: "node_remote",
        code: "federated_node_unavailable",
        message: "Federated node was unavailable.",
        source: "remote"
      }
    })

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [repo["repoId"]],
        "refs" => %{repo["repoId"] => "refs/heads/main"},
        "paths" => %{repo["repoId"] => ["docs/**"]},
        "query" => "remote",
        "includeErrors" => false
      })
      |> json!(502)

    assert body["error"]["code"] == "federated_partial_failure"
  end

  test "missing remote node base url maps to route_not_configured", %{conn: conn} do
    token = dev_token!(conn)
    repo = remote_repo!(token, "missing_node")

    body =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/search", %{
        "repoIds" => [repo["repoId"]],
        "refs" => %{repo["repoId"] => "refs/heads/main"},
        "paths" => %{repo["repoId"] => ["docs/**"]},
        "query" => "remote",
        "includeErrors" => true
      })
      |> json!(200)

    assert [%{"code" => "federated_route_not_configured"}] = body["search"]["errors"]
  end

  defp remote_repo!(token, node_id) do
    {:ok, _} = TreeDb.Store.seed_dev_records("node_remote", "http://node-remote.example.test")
    path = Path.join(TreeDb.Store.data_dir(), "repos/bare/federated-remote-#{node_id}")
    create_git_repo!(path)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "federated-remote-#{node_id}",
        "localPath" => path
      })["repo"]

    {:ok, _placement} =
      TreeDb.Store.put_repository_placement(%{
        repositoryId: repo["repoId"],
        primaryNodeId: node_id,
        mirrorNodeIds: [],
        readPolicy: "primary_or_mirror",
        writePolicy: "primary_only",
        migrationState: "stable"
      })

    repo
  end
end
