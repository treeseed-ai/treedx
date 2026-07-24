defmodule TreeDxProfiler.ScenarioSetupExtensions do
  @moduledoc false

  alias TreeDxProfiler.FederationScenario

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_ok: 1,
      assert_ok_or_expected_error: 1,
      assert_ok_or_forbidden: 1,
      assert_ok_or_not_found: 1,
      assert_ok_or_unavailable: 1,
      call: 7,
      call!: 7,
      call!: 8
    ]

  def run_federation_setup(%{opts: %{include_federation: true}} = state) do
    state = FederationScenario.setup(state)
    repo_id = primary_repo(state).repo_id
    ref = Map.get(state, :branch_name, "refs/heads/main")

    state =
      state
      |> call!(
        :get,
        "/api/v1/federation/peers",
        "listFederationPeers",
        "federation",
        nil,
        &assert_ok_or_forbidden/1
      )
      |> maybe_get_federation_peer()
      |> call!(
        :get,
        "/api/v1/federation/routes",
        "listFederationRoutes",
        "federation",
        nil,
        &assert_ok_or_forbidden/1
      )

    {state, catalog_response} =
      call(
        state,
        :get,
        "/api/v1/federation/catalog",
        "getFederationCatalog",
        "federation",
        nil,
        expected: 200,
        assert: &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/federation/catalog/push",
        "pushFederationCatalog",
        "federation",
        %{"catalog" => catalog_response["catalog"] || %{}},
        &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/federation/catalog/sync",
        "syncFederationCatalog",
        "federation",
        %{},
        &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/federation/query/plan",
        "planFederationQuery",
        "federation",
        %{
          "repoIds" => [repo_id],
          "refs" => %{repo_id => ref},
          "paths" => %{repo_id => ["docs/**"]},
          "queryType" => "text",
          "capabilities" => ["files:search"]
        },
        &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/search",
        "federatedSearch",
        "federation",
        %{
          "repoIds" => [repo_id],
          "refs" => %{repo_id => ref},
          "paths" => %{repo_id => ["docs/**"]},
          "query" => "release",
          "limit" => 20,
          "includeErrors" => true
        },
        &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/query",
        "federatedQuery",
        "federation",
        %{
          "repoIds" => [repo_id],
          "refs" => %{repo_id => ref},
          "paths" => %{repo_id => ["docs/**"]},
          "type" => "combined",
          "query" => "release",
          "limit" => 20,
          "includeErrors" => true
        },
        &assert_ok_or_forbidden/1
      )

    state =
      call!(
        state,
        :post,
        "/api/v1/context/build",
        "federatedContextBuild",
        "federation",
        %{
          "repoIds" => [repo_id],
          "refs" => %{repo_id => ref},
          "paths" => %{repo_id => ["docs/**"]},
          "query" => "release",
          "budget" => %{"maxNodes" => 10, "maxTokens" => 2000},
          "includeErrors" => true
        },
        &assert_ok_or_forbidden/1
      )

    call!(
      state,
      :post,
      "/api/v1/graph/query",
      "federatedGraphQuery",
      "federation",
      %{
        "repoIds" => [repo_id],
        "refs" => %{repo_id => ref},
        "paths" => %{repo_id => ["docs/**"]},
        "query" => "release",
        "options" => %{"limit" => 20},
        "includeErrors" => true
      },
      &assert_ok_or_forbidden/1
    )
  end

  def run_federation_setup(state), do: state

  defp maybe_get_federation_peer(%{federation_nodes: nodes} = state) when is_list(nodes) do
    case Enum.find(nodes, &(&1.id == "node_b")) do
      nil ->
        state

      node ->
        call!(
          state,
          :get,
          "/api/v1/federation/peers/#{node.node_id}",
          "getFederationPeer",
          "federation",
          nil,
          &assert_ok_or_forbidden/1
        )
    end
  end

  defp maybe_get_federation_peer(state), do: state

  def run_admin_storage(%{opts: %{include_admin: true}} = state) do
    state =
      state
      |> call!(
        :get,
        "/api/v1/admin/health/deep",
        "getAdminDeepHealth",
        "operations",
        nil,
        &assert_ok_or_unavailable/1,
        expected: [200, 503]
      )
      |> call!(
        :get,
        "/api/v1/admin/workspaces/quarantined",
        "listQuarantinedWorkspaces",
        "admin",
        nil,
        &assert_ok/1
      )
      |> call!(
        :get,
        "/api/v1/admin/storage/health",
        "getAdminStorageHealth",
        "admin",
        nil,
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/admin/storage/check",
        "checkAdminStorage",
        "admin",
        %{},
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/admin/storage/recover",
        "recoverAdminStorage",
        "admin",
        %{"force" => true},
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/admin/storage/compact",
        "compactAdminStorage",
        "admin",
        %{"planOnly" => true, "backupBefore" => false},
        &assert_ok/1
      )

    {state, backup} =
      call(
        state,
        :post,
        "/api/v1/admin/storage/backup",
        "backupAdminStorage",
        "admin",
        %{"verify" => true},
        expected: 200,
        assert: &assert_ok/1
      )

    backup_id = get_in(backup, ["backup", "backupId"])

    {state, migration} =
      call(
        state,
        :post,
        "/api/v1/admin/storage/migrations/apply",
        "applyStorageMigration",
        "admin",
        %{
          "targetVersion" => "profiler_#{state.opts.profile_id}",
          "backupBefore" => false
        },
        expected: 200,
        assert: &assert_ok/1
      )

    migration_id = get_in(migration, ["migration", "migrationId"])

    state =
      state
      |> Map.put(:backup_id, backup_id)
      |> Map.put(:storage_migration_id, migration_id)
      |> call!(
        :get,
        "/api/v1/admin/storage/migrations",
        "listStorageMigrations",
        "admin",
        nil,
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/admin/storage/migrations/plan",
        "planStorageMigration",
        "admin",
        %{"targetVersion" => "profiler_plan_#{state.opts.profile_id}"},
        &assert_ok/1
      )

    state =
      if migration_id do
        call!(
          state,
          :post,
          "/api/v1/admin/storage/migrations/rollback",
          "rollbackStorageMigration",
          "admin",
          %{"migrationId" => migration_id},
          &assert_ok/1
        )
      else
        state
      end

    state =
      if backup_id do
        state
        |> call!(
          :post,
          "/api/v1/admin/storage/restore/verify",
          "verifyStorageRestore",
          "admin",
          %{"backupId" => backup_id},
          &assert_ok/1
        )
        |> call!(
          :post,
          "/api/v1/admin/storage/restore",
          "restoreStorage",
          "admin",
          %{
            "backupId" => backup_id,
            "planOnly" => true,
            "backupBeforeRestore" => false
          },
          &assert_ok/1
        )
      else
        state
      end

    if state.opts.include_destructive do
      call!(
        state,
        :post,
        "/api/v1/admin/artifacts/cleanup",
        "cleanupArtifacts",
        "artifact",
        %{"planOnly" => true},
        &assert_ok_or_expected_error/1,
        expected: [200, 422]
      )
    else
      state
    end
  end

  def run_admin_storage(state), do: state

  def run_post_measured_operations(%{opts: %{include_destructive: true}} = state) do
    repo_id = primary_repo(state).repo_id

    state =
      if is_binary(state[:artifact_id]) do
        call!(
          state,
          :delete,
          "/api/v1/repos/#{repo_id}/artifacts/#{state.artifact_id}",
          "deleteArtifact",
          "artifact",
          nil,
          &assert_ok_or_not_found/1,
          expected: [200, 404]
        )
      else
        state
      end

    if is_binary(state[:workspace_id]) do
      call!(
        state,
        :post,
        "/api/v1/workspaces/#{state.workspace_id}/close",
        "closeWorkspace",
        "workspace",
        %{"reason" => "profiler complete"},
        &assert_ok/1
      )
    else
      state
    end
  end

  def run_post_measured_operations(state), do: state

  defp primary_repo(state), do: hd(state.fixture.local_repos)
end
