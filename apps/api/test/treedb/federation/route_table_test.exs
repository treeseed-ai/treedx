defmodule TreeDb.Federation.RouteTableTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "treedb-route-table-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDb.Store.seed_dev_records("node_local", "http://localhost:4000")

    System.put_env("TREEDB_FEDERATION_LOAD_AWARE_READS", "true")
    System.put_env("TREEDB_FEDERATION_LOAD_AWARE_READ_PRESSURE", "moderate")

    on_exit(fn ->
      System.delete_env("TREEDB_FEDERATION_LOAD_AWARE_READS")
      System.delete_env("TREEDB_FEDERATION_LOAD_AWARE_READ_PRESSURE")
      File.rm_rf!(dir)
    end)

    :ok
  end

  test "load-aware reads prefer a fresh trusted mirror when local primary reaches configured threshold" do
    System.put_env("TREEDB_FEDERATION_LOAD_AWARE_READ_PRESSURE", "low")
    repo_id = "repo_route_table_load"
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    {:ok, _peer} =
      TreeDb.Federation.Trust.put_peer(%{
        "id" => "node_mirror",
        "baseUrl" => "http://node-mirror.example.test",
        "relationship" => "peer",
        "trustStates" => ["registered", "trusted_for_query"],
        "canReceiveQueries" => true,
        "canMirrorRepos" => true,
        "lastSeenAt" => now
      })

    {:ok, _placement} =
      TreeDb.Store.put_repository_placement(%{
        repositoryId: repo_id,
        primaryNodeId: "node_local",
        mirrorNodeIds: ["node_mirror"],
        readPolicy: "primary_or_healthy_mirror",
        writePolicy: "primary_proxy",
        migrationState: "stable"
      })

    {:ok, _assignment} =
      TreeDb.Store.put_mirror_assignment(%{
        id: "mirror_#{repo_id}_node_local_node_mirror",
        repositoryId: repo_id,
        sourceNodeId: "node_local",
        targetNodeId: "node_mirror",
        mode: "full",
        promotionEligible: true,
        freshnessRequirement: %{},
        status: "synced",
        lastSyncedCommit: "abc123",
        lastSyncAt: now,
        createdAt: now
      })

    assert {:ok, route} =
             TreeDb.Federation.RouteTable.resolve_read(repo_id, pool: :repository_query)

    assert route["servedByNodeId"] == "node_mirror"
    assert route["reason"] == "remote_mirror"
    assert route["source"] == "remote"
  end

  test "writes stay on the primary and never select mirrors" do
    repo_id = "repo_route_table_write"

    {:ok, _placement} =
      TreeDb.Store.put_repository_placement(%{
        repositoryId: repo_id,
        primaryNodeId: "node_local",
        mirrorNodeIds: ["node_mirror"],
        readPolicy: "primary_or_healthy_mirror",
        writePolicy: "primary_proxy",
        migrationState: "stable"
      })

    assert {:ok, route} = TreeDb.Federation.RouteTable.resolve_write(repo_id)
    assert route["servedByNodeId"] == "node_local"
    assert route["source"] == "local"
  end
end
