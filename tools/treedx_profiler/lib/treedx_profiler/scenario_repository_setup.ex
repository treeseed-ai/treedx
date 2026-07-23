defmodule TreeDxProfiler.ScenarioRepositorySetup do
  @moduledoc false

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_ok: 1,
      assert_ok_or_expected_error: 1,
      assert_truthy: 2,
      call: 7,
      call!: 7,
      call!: 8
    ]

  def register_repos(state) do
    Enum.reduce(state.fixture.local_repos, state, fn repo, acc ->
      body = %{
        "repositoryName" => repo.name,
        "sourceRelativePath" => source_relative_path(repo.path, acc.opts)
      }

      {next, response} =
        call(
          acc,
          :post,
          "/api/v1/admin/repos/import-local",
          "importLocalRepository",
          "repository",
          body,
          expected: 200,
          assert: fn payload ->
            assert_truthy(get_in(payload, ["repo", "repoId"]), "registered repo id")
          end
        )

      registered = Map.put(repo, :repo_id, get_in(response, ["repo", "repoId"]))

      update_in(next.fixture.local_repos, fn repos ->
        replace_repo(repos, repo.name, registered)
      end)
    end)
  end

  defp source_relative_path(path, opts) do
    data_dir =
      System.get_env("TREEDX_DATA_DIR") ||
        opts[:data_dir] ||
        "/var/lib/treedx"

    path
    |> Path.expand()
    |> Path.relative_to(Path.expand(data_dir))
  end

  def configure_repo(state) do
    repo = primary_repo(state)
    repo_id = repo.repo_id

    state
    |> call!(:get, "/api/v1/repos", "listRepositories", "repository", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/repos/#{repo_id}", "getRepository", "repository", nil, &assert_ok/1)
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/status",
      "getRepositoryStatus",
      "repository",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/refs",
      "listRepositoryRefs",
      "repository",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/remotes",
      "listRepositoryRemotes",
      "repository",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/policy/effective-scope?repoId=#{repo_id}",
      "getEffectiveScope",
      "policy",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/policy/refresh",
      "refreshPolicy",
      "policy",
      %{"repoId" => repo_id},
      &assert_ok/1
    )
    |> call!(:get, "/api/v1/node", "getLocalNode", "registry", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/registry/nodes", "listRegistryNodes", "registry", nil, &assert_ok/1)
    |> call!(
      :get,
      "/api/v1/registry/repos/#{repo_id}/placement",
      "getRepositoryPlacement",
      "registry",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/registry/repos/#{repo_id}/placement",
      "putRepositoryPlacement",
      "registry",
      %{
        "primaryNodeId" => primary_node_id(state),
        "mirrorNodeIds" => [],
        "readPolicy" => "primary_or_mirror",
        "writePolicy" => "primary_only",
        "migrationState" => "stable"
      },
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/policy/grants",
      "putCapabilityGrant",
      "policy",
      %{
        "actorId" => "actor_profiler_limited",
        "tenantId" => "tenant_demo",
        "repoId" => repo_id,
        "capabilities" => ["files:read", "files:search", "graph:query"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      },
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/sync",
      "syncRepository",
      "repository",
      %{"planOnly" => true},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/push",
      "pushRepository",
      "repository",
      %{
        "remoteUrl" => repo.path,
        "remoteName" => "profiler",
        "refspecs" => ["refs/heads/main:refs/heads/profile-push-plan"],
        "planOnly" => true
      },
      &assert_ok_or_expected_error/1,
      expected: [200, 409, 422]
    )
    |> setup_mirror_and_migration(repo_id)
    |> call!(
      :get,
      "/api/v1/audit/events?repoId=#{repo_id}&limit=100",
      "listAuditEvents",
      "policy",
      nil,
      &assert_ok/1
    )
  end

  def create_workspace(state) do
    repo = primary_repo(state)
    repo_id = repo.repo_id

    {state, response} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/workspaces",
        "createWorkspace",
        "workspace",
        %{
          "baseRef" => "refs/heads/main",
          "branchName" => "refs/heads/profiler/#{state.opts.profile_id}",
          "mode" => "writable",
          "allowedPaths" => [
            "docs/**",
            "plain/**",
            "data/**",
            "assets/**",
            "workspace/**",
            "package.json"
          ]
        },
        expected: 200,
        assert: fn payload -> assert_truthy(payload["workspaceId"], "workspace id") end
      )

    state
    |> Map.put(:workspace_id, response["workspaceId"])
    |> call!(
      :get,
      "/api/v1/workspaces/#{response["workspaceId"]}",
      "getWorkspace",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/workspaces/#{response["workspaceId"]}/tree",
      "listWorkspaceTree",
      "workspace",
      nil,
      &assert_ok/1
    )
  end

  def setup_mirror_and_migration(state, repo_id) do
    mirror_id = "mirror_#{state.opts.profile_id}"
    source_node_id = primary_node_id(state)
    target_node_id = mirror_target_node_id(state)

    {state, _mirror} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/mirrors",
        "putMirror",
        "mirror",
        %{
          "id" => mirror_id,
          "sourceNodeId" => source_node_id,
          "targetNodeId" => target_node_id,
          "mode" => "read_replica",
          "status" => "synced",
          "behindBy" => 0
        },
        expected: 200,
        assert: &assert_ok/1
      )

    {state, migration} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/migrations",
        "createMigration",
        "migration",
        %{
          "targetNodeId" => target_node_id,
          "sourceNodeId" => source_node_id,
          "mode" => "primary_transfer",
          "planOnly" => true,
          "requireMirrorSynced" => false
        },
        expected: [200, 409, 422],
        assert: &assert_ok_or_expected_error/1
      )

    migration_id =
      get_in(migration, ["migration", "id"]) || get_in(migration, ["migration", "migrationId"])

    state =
      state
      |> Map.put(:mirror_id, mirror_id)
      |> Map.put(:migration_id, migration_id)
      |> call!(
        :get,
        "/api/v1/repos/#{repo_id}/mirrors",
        "listMirrors",
        "mirror",
        nil,
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/repos/#{repo_id}/mirrors/#{mirror_id}/sync",
        "syncMirror",
        "mirror",
        %{
          "remoteUrl" => primary_repo(state).path,
          "remoteName" => "profiler",
          "planOnly" => true
        },
        &assert_ok_or_expected_error/1,
        expected: [200, 409, 422]
      )
      |> call!(
        :post,
        "/api/v1/repos/#{repo_id}/mirrors/#{mirror_id}/health",
        "checkMirrorHealth",
        "mirror",
        %{},
        &assert_ok/1
      )
      |> call!(
        :post,
        "/api/v1/repos/#{repo_id}/mirrors/#{mirror_id}/promote",
        "promoteMirror",
        "mirror",
        %{"planOnly" => true, "requireSynced" => false},
        &assert_ok/1
      )

    if migration_id do
      call!(
        state,
        :get,
        "/api/v1/repos/#{repo_id}/migrations/#{migration_id}",
        "getMigration",
        "migration",
        nil,
        &assert_ok/1
      )
    else
      state
    end
  end

  defp primary_repo(state), do: hd(state.fixture.local_repos)

  defp primary_node_id(%{opts: %{federation_mode: mode}}) when mode != "single_node",
    do: "node_a"

  defp primary_node_id(_state), do: "node_local"

  defp mirror_target_node_id(%{opts: %{federation_mode: "mirror_cluster"}}), do: "node_b"
  defp mirror_target_node_id(state), do: primary_node_id(state)

  defp replace_repo(repos, name, repo),
    do: Enum.map(repos, fn existing -> if existing.name == name, do: repo, else: existing end)
end
