defmodule TreeDbProfiler.ScenarioRunner do
  @moduledoc false

  alias TreeDbProfiler.{
    EndpointMatrix,
    EndpointConsistency,
    DelayedCheckScheduler,
    FaultInjection,
    FederationScenario,
    Fixtures,
    HTTP,
    LeakDetector,
    MetamorphicChecker,
    ModelState,
    NegativeRequestGenerator,
    OpenApiResponseValidator,
    OperationChain,
    PermissionMatrix,
    PortfolioState,
    ProbePolicy,
    ProfileRequest,
    Reconciler,
    ReliabilityBudget,
    ReplayLog,
    RestartDurability,
    Sampler,
    Scheduler,
    Stats,
    SystemProfile,
    Validation,
    ValidationProbe
  }

  def run(opts) do
    profile_window = start_window()
    setup_window = start_window()
    started = profile_window.started_at
    profile_id = opts.profile_id

    fixture =
      Fixtures.generate!(fixture_id_for(opts),
        profile_id: profile_id,
        repo_prefix: repo_prefix_for(opts),
        fixture_root: opts.fixture_root,
        size: opts.size,
        seed: opts.seed
      )

    client = HTTP.new(opts)

    state = %{
      opts: opts,
      client: client,
      fixture: fixture,
      samples: [],
      assertions: [],
      timing: %{"profile" => profile_window, "setup" => setup_window}
    }

    final_state =
      if opts.load_mode == "portfolio" do
        run_portfolio(state)
      else
        state
        |> authenticate()
        |> capture_metrics(:before)
        |> run_setup()
        |> end_setup_window()
        |> run_warmup()
        |> run_measured()
        |> run_post_measured_operations()
        |> capture_metrics(:after)
      end

    final_state =
      final_state
      |> run_cleanup()
      |> put_in([:timing, "profile"], end_window(final_state.timing["profile"]))

    report = build_report(final_state, started)
    report
  end

  defp fixture_id_for(%{load_mode: "portfolio", fixture: "all"}), do: "small-docs"
  defp fixture_id_for(%{load_mode: "portfolio", fixture: fixture}), do: fixture
  defp fixture_id_for(opts), do: opts.fixture

  defp repo_prefix_for(%{load_mode: "portfolio"} = opts), do: opts.portfolio_repo_prefix
  defp repo_prefix_for(opts), do: opts.repo_prefix

  defp start_window do
    %{started_at: DateTime.utc_now(), started_at_ms: System.monotonic_time(:millisecond)}
  end

  defp end_window(%{started_at: started_at, started_at_ms: started_at_ms}) do
    ended_at = DateTime.utc_now()
    ended_at_ms = System.monotonic_time(:millisecond)

    %{
      "startedAt" => DateTime.to_iso8601(started_at),
      "endedAt" => DateTime.to_iso8601(ended_at),
      "startedAtMs" => started_at_ms,
      "endedAtMs" => ended_at_ms,
      "durationMs" => ended_at_ms - started_at_ms
    }
  end

  defp scheduler_window(scheduler) do
    %{
      "requestedDurationMs" => scheduler.requested_duration_ms,
      "startedAt" => scheduler.started_at,
      "endedAt" => scheduler.ended_at,
      "startedAtMs" => scheduler.started_at_ms,
      "endedAtMs" => scheduler.ended_at_ms,
      "durationMs" => scheduler.duration_ms,
      "durationSatisfied" => scheduler.duration_satisfied,
      "minimumMeasuredDurationMs" => scheduler.minimum_measured_duration_ms,
      "stopReason" => scheduler.stop_reason
    }
  end

  defp end_setup_window(state),
    do: put_in(state, [:timing, "setup"], end_window(state.timing["setup"]))

  defp run_cleanup(state) do
    window = start_window()
    cleanup_fixture(state)
    put_in(state, [:timing, "cleanup"], end_window(window))
  end

  defp run_portfolio(state) do
    state =
      state
      |> authenticate()
      |> capture_metrics(:before)
      |> run_setup()

    {:ok, portfolio_pid} = PortfolioState.start_link(%{state.opts | fixture: state.fixture})

    seed_portfolio_from_setup(portfolio_pid, state)
    state = ensure_initial_portfolio_repos(state, portfolio_pid)
    state = put_in(state, [:timing, "setup"], end_window(state.timing["setup"]))

    scheduler =
      Scheduler.run(state, portfolio_pid, state.opts, fn execution_state, request ->
        execute_profile_request(execution_state, request)
      end)

    portfolio_snapshot = PortfolioState.snapshot(portfolio_pid)

    state
    |> Map.put(:samples, state.samples ++ scheduler.samples)
    |> Map.put(:http_samples, (state[:http_samples] || state.samples) ++ scheduler.http_samples)
    |> Map.put(:assertions, state.assertions ++ scheduler.assertions)
    |> Map.put(:portfolio, portfolio_snapshot.final)
    |> Map.put(:portfolio_runtime, portfolio_snapshot)
    |> Map.put(:request_samples, Sampler.report(scheduler.sampler, state.opts.include_requests))
    |> Map.put(:scheduler, %{
      "startedAt" => scheduler.started_at,
      "endedAt" => scheduler.ended_at,
      "workerCount" => scheduler.worker_count,
      "startedAtMs" => scheduler.started_at_ms,
      "endedAtMs" => scheduler.ended_at_ms,
      "durationMs" => scheduler.duration_ms,
      "requestedDurationMs" => scheduler.requested_duration_ms,
      "minimumMeasuredDurationMs" => scheduler.minimum_measured_duration_ms,
      "durationSatisfied" => scheduler.duration_satisfied,
      "stopReason" => scheduler.stop_reason
    })
    |> put_in([:timing, "measured"], scheduler_window(scheduler))
    |> run_post_measured_operations()
    |> capture_metrics(:after)
  end

  defp seed_portfolio_from_setup(portfolio_pid, state) do
    if state[:snapshot_id] do
      PortfolioState.apply_effect(portfolio_pid, %{
        kind: :snapshot_built,
        snapshot_id: state.snapshot_id,
        repo_id: primary_repo(state).repo_id
      })
    end

    if state[:artifact_id] do
      PortfolioState.apply_effect(portfolio_pid, %{
        kind: :artifact_exported,
        artifact_id: state.artifact_id,
        repo_id: primary_repo(state).repo_id
      })
    end
  end

  defp ensure_initial_portfolio_repos(state, portfolio_pid) do
    target = max(state.opts.portfolio_initial_repos, 1)

    Enum.reduce(1..max(target - 1, 0)//1, state, fn _, acc ->
      request = TreeDbProfiler.RequestGenerator.build(:create_repository, portfolio_pid, acc.opts)
      {sample, response, assertion} = execute_profile_request(acc, request)

      if assertion.passed do
        request.state_effect
        |> Map.put(:repo_id, get_in(response, ["repo", "repoId"]))
        |> then(&PortfolioState.apply_effect(portfolio_pid, &1))
      end

      %{
        acc
        | samples: acc.samples ++ [sample],
          assertions: acc.assertions ++ [assertion]
      }
    end)
  end

  defp authenticate(%{opts: %{auth_mode: "bearer", token: token}} = state)
       when is_binary(token) and token != "" do
    put_in(state.client.token, token)
  end

  defp authenticate(%{opts: %{auth_mode: "dev"}} = state) do
    {state, body} =
      call(state, :post, "/api/v1/auth/dev-token", "createDevToken", "auth", %{},
        expected: 200,
        measured?: true
      )

    token = body["accessToken"] || get_in(body, ["token", "accessToken"])
    put_in(state.client.token, token)
  end

  defp authenticate(_state), do: raise("bearer auth requires --token")

  defp capture_metrics(%{opts: %{metrics: false}} = state, key),
    do: Map.put(state, :"metrics_#{key}", nil)

  defp capture_metrics(state, key) do
    {state, body} =
      call(state, :get, "/api/v1/metrics", "getMetrics", "operations", nil,
        expected: 200,
        measured?: true
      )

    Map.put(state, :"metrics_#{key}", body["metrics"] || %{})
  end

  defp run_setup(state) do
    state
    |> call!(:get, "/api/v1/health", "getHealth", "operations", nil, &assert_ok/1)
    |> call!(
      :get,
      "/metrics",
      "getPrometheusMetrics",
      "operations",
      nil,
      &assert_binary_or_ok/1
    )
    |> call!(
      :get,
      "/api/v1/ready",
      "getReadiness",
      "operations",
      nil,
      &assert_ok_or_unavailable/1
    )
    |> call!(
      :get,
      "/api/v1/health/deep",
      "getDeepHealth",
      "operations",
      nil,
      &assert_ok_or_unavailable/1
    )
    |> call!(:get, "/api/v1/version", "getVersion", "operations", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/auth/whoami", "getWhoami", "auth", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/auth/mode", "getAuthMode", "auth", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/policy/capabilities", "listCapabilities", "policy", nil, &assert_ok/1)
    |> call!(:get, "/api/v1/policy/grants", "listCapabilityGrants", "policy", nil, &assert_ok/1)
    |> register_repos()
    |> run_federation_setup()
    |> configure_repo()
    |> FederationScenario.setup_spillover_probe()
    |> create_workspace()
    |> mutate_workspace()
    |> refresh_graph_and_index()
    |> build_snapshot_artifact()
    |> run_admin_storage()
  end

  defp register_repos(state) do
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
      System.get_env("TREEDB_DATA_DIR") ||
        opts[:data_dir] ||
        "/var/lib/treedb"

    path
    |> Path.expand()
    |> Path.relative_to(Path.expand(data_dir))
  end

  defp configure_repo(state) do
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
      %{"dryRun" => true},
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
        "refspecs" => ["refs/heads/main:refs/heads/profile-push-dry-run"],
        "dryRun" => true
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

  defp create_workspace(state) do
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

  defp setup_mirror_and_migration(state, repo_id) do
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
          "dryRun" => true,
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
        %{"remoteUrl" => primary_repo(state).path, "remoteName" => "profiler", "dryRun" => true},
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
        %{"dryRun" => true, "requireSynced" => false},
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

  defp mutate_workspace(state) do
    ws = state.workspace_id
    content = "# Profiler Update\n\nrelease provenance updated through workspace\n"
    patch = "+++\n# Profiler Patch\n\nrelease patched through workspace\n"
    blob = Base.encode64("profiler binary payload #{state.opts.profile_id}")

    {state, _} =
      call(
        state,
        :put,
        "/api/v1/workspaces/#{ws}/files?path=docs/profiler-update.md",
        "writeWorkspaceFile",
        "workspace",
        %{"content" => content},
        expected: 200,
        assert: fn payload -> assert_path(payload, "docs/profiler-update.md") end
      )

    state
    |> call!(
      :put,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-delete.md",
      "writeWorkspaceFile",
      "workspace",
      %{"content" => "release delete target #{state.opts.profile_id}\n"},
      &assert_ok/1
    )
    |> call!(
      :patch,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-patch.md",
      "patchWorkspaceFile",
      "workspace",
      %{"content" => patch},
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
    |> maybe_delete_workspace_file()
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-update.md",
      "readWorkspaceFile",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/search",
      "searchWorkspace",
      "workspace",
      %{"query" => "release", "paths" => ["docs/**"]},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/blobs/write",
      "writeWorkspaceBlob",
      "blob",
      %{
        "path" => "assets/profiler.bin",
        "encoding" => "base64",
        "contentBase64" => blob,
        "contentType" => "application/octet-stream"
      },
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/blobs/download?path=assets/profiler.bin",
      "downloadWorkspaceBlob",
      "blob",
      nil,
      &assert_binary_or_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/blobs/delete",
      "deleteWorkspaceBlob",
      "blob",
      %{"path" => "assets/profiler-deleted.bin"},
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
    |> call!(
      :put,
      "/api/v1/workspaces/#{ws}/blobs/upload?path=assets/direct-upload.bin",
      "uploadWorkspaceBlob",
      "blob",
      "direct upload payload #{state.opts.profile_id}",
      &assert_ok/1,
      headers: [{"content-type", "application/octet-stream"}]
    )
    |> abort_multipart_upload()
    |> multipart_roundtrip()
    |> maybe_exec_workspace()
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/status",
      "getWorkspaceStatus",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/diff",
      "getWorkspaceDiff",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> commit_workspace()
  end

  defp maybe_delete_workspace_file(%{opts: %{include_destructive: true}} = state) do
    call!(
      state,
      :delete,
      "/api/v1/workspaces/#{state.workspace_id}/files?path=docs/profiler-delete.md",
      "deleteWorkspaceFile",
      "workspace",
      nil,
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
  end

  defp maybe_delete_workspace_file(state), do: state

  defp maybe_exec_workspace(%{opts: %{include_exec: true}} = state) do
    call!(
      state,
      :post,
      "/api/v1/workspaces/#{state.workspace_id}/exec",
      "execWorkspace",
      "exec",
      %{
        "mode" => "read_only",
        "cmd" => "pwd",
        "timeoutMs" => 10_000,
        "maxOutputBytes" => 4096
      },
      &assert_ok/1
    )
  end

  defp maybe_exec_workspace(state), do: state

  defp multipart_roundtrip(state) do
    ws = state.workspace_id
    payload = "multipart profiler payload #{state.opts.profile_id}"

    {state, create} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads",
        "createWorkspaceBlobUpload",
        "blob",
        %{
          "path" => "assets/multipart.txt",
          "contentType" => "text/plain",
          "expectedByteLength" => byte_size(payload)
        },
        expected: [200, 201],
        assert: &assert_ok/1
      )

    upload_id =
      get_in(create, ["upload", "uploadId"]) || get_in(create, ["session", "uploadId"]) ||
        create["uploadId"]

    if upload_id do
      state
      |> call!(
        :put,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}/parts/1",
        "uploadWorkspaceBlobPart",
        "blob",
        payload,
        &assert_ok/1,
        headers: [{"content-type", "application/octet-stream"}]
      )
      |> call!(
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}/complete",
        "completeWorkspaceBlobUpload",
        "blob",
        %{},
        &assert_ok/1
      )
    else
      state
    end
  end

  defp abort_multipart_upload(state) do
    ws = state.workspace_id

    {state, create} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads",
        "createWorkspaceBlobUpload",
        "blob",
        %{
          "path" => "assets/aborted-upload.txt",
          "contentType" => "text/plain",
          "expectedByteLength" => 24
        },
        expected: [200, 201],
        assert: &assert_ok/1
      )

    upload_id =
      get_in(create, ["upload", "uploadId"]) || get_in(create, ["session", "uploadId"]) ||
        create["uploadId"]

    if upload_id do
      call!(
        state,
        :delete,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}",
        "abortWorkspaceBlobUpload",
        "blob",
        nil,
        &assert_ok/1
      )
    else
      state
    end
  end

  defp commit_workspace(state) do
    ws = state.workspace_id

    {state, response} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/commit",
        "commitWorkspace",
        "workspace",
        %{
          "message" => "Profiler update",
          "author" => %{"name" => "TreeDB Profiler", "email" => "profiler@example.invalid"}
        },
        expected: 200,
        assert: fn payload -> assert_truthy(payload["commitSha"], "commit sha") end
      )

    Map.put(
      state,
      :branch_name,
      response["branchName"] || "refs/heads/profiler/#{state.opts.profile_id}"
    )
  end

  defp refresh_graph_and_index(state) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    paths = ["docs/**", "plain/**", "data/**"]

    {state, refresh} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/refresh",
        "refreshRepositoryGraph",
        "graph",
        %{"ref" => ref, "paths" => paths, "incremental" => false},
        expected: 200,
        assert: &assert_ok/1
      )

    job_id = refresh["jobId"] || get_in(refresh, ["graph", "jobId"])

    state =
      if job_id do
        call!(
          state,
          :get,
          "/api/v1/repos/#{repo_id}/graph/refresh-jobs/#{job_id}",
          "getGraphRefreshJob",
          "graph",
          nil,
          &assert_ok/1
        )
      else
        state
      end

    state =
      call!(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/query",
        "queryRepositoryGraph",
        "graph",
        %{"ref" => ref, "query" => "release", "options" => %{"limit" => 20}},
        &assert_ok/1
      )

    {state, files} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/search-files",
        "searchGraphFiles",
        "graph",
        %{"ref" => ref, "query" => "release", "limit" => 20},
        expected: 200,
        assert: &assert_ok/1
      )

    graph_node_id = get_in(files, ["results", Access.at(0), "node", "id"])

    state
    |> Map.put(:graph_node_id, graph_node_id)
    |> maybe_get_graph_node(repo_id, ref)
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/search-sections",
      "searchGraphSections",
      "graph",
      %{"ref" => ref, "query" => "release", "limit" => 20},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/search-entities",
      "searchGraphEntities",
      "graph",
      %{"ref" => ref, "query" => "release", "limit" => 20},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/related",
      "getRelatedGraphNodes",
      "graph",
      related_graph_body(ref, graph_node_id),
      &assert_ok_or_validation/1,
      expected: [200, 422]
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/subgraph",
      "getGraphSubgraph",
      "graph",
      %{
        "ref" => ref,
        "seedIds" => List.wrap(graph_node_id) |> Enum.reject(&is_nil/1),
        "options" => %{"limit" => 5}
      },
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/context/build",
      "buildContext",
      "context",
      %{"ref" => ref, "query" => "release", "budget" => %{"maxNodes" => 10, "maxTokens" => 2000}},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/context/parse-ctx",
      "parseContextQuery",
      "context",
      %{"ctx" => "release"},
      &assert_ok_or_validation/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/search/index/refresh",
      "refreshSearchIndex",
      "search",
      %{"ref" => ref, "paths" => paths, "incremental" => false},
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/search/index/status",
      "getSearchIndexStatus",
      "search",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/search/index/compact",
      "compactSearchIndex",
      "search",
      %{"dryRun" => true},
      &assert_ok_or_forbidden/1
    )
  end

  defp maybe_get_graph_node(%{graph_node_id: node_id} = state, repo_id, ref)
       when is_binary(node_id) do
    call!(
      state,
      :get,
      "/api/v1/repos/#{repo_id}/graph/nodes/#{node_id}?ref=#{URI.encode_www_form(ref)}",
      "getGraphNode",
      "graph",
      nil,
      &assert_ok/1
    )
  end

  defp maybe_get_graph_node(state, _repo_id, _ref), do: state

  defp related_graph_body(ref, node_id) when is_binary(node_id) do
    %{
      "ref" => ref,
      "nodeId" => node_id,
      "relations" => ["references"],
      "options" => %{"limit" => 5}
    }
  end

  defp related_graph_body(ref, _node_id),
    do: %{"ref" => ref, "options" => %{"limit" => 5}}

  defp build_snapshot_artifact(state) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"

    {state, snapshot} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/snapshots/build",
        "buildSnapshot",
        "snapshot",
        %{
          "ref" => ref,
          "kind" => "repository_snapshot",
          "paths" => ["docs/**"],
          "includeGraph" => true
        },
        expected: 200,
        assert: &assert_ok/1
      )

    snapshot_id = get_in(snapshot, ["snapshot", "snapshotId"])

    state =
      if snapshot_id do
        call!(
          state,
          :get,
          "/api/v1/repos/#{repo_id}/snapshots/#{snapshot_id}",
          "getSnapshot",
          "snapshot",
          nil,
          &assert_ok/1
        )
      else
        state
      end

    {state, artifact} =
      if snapshot_id do
        call(
          state,
          :post,
          "/api/v1/repos/#{repo_id}/artifacts/export",
          "exportArtifact",
          "artifact",
          %{"snapshotId" => snapshot_id},
          expected: 200,
          assert: &assert_ok/1
        )
      else
        {state, %{}}
      end

    artifact_id = get_in(artifact, ["artifact", "artifactId"])

    state
    |> Map.put(:snapshot_id, snapshot_id)
    |> Map.put(:artifact_id, artifact_id)
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/artifacts",
      "listArtifacts",
      "artifact",
      nil,
      &assert_ok/1
    )
    |> maybe_get_artifact(repo_id, artifact_id)
  end

  defp maybe_get_artifact(state, _repo_id, nil), do: state

  defp maybe_get_artifact(state, repo_id, artifact_id),
    do:
      call!(
        state,
        :get,
        "/api/v1/repos/#{repo_id}/artifacts/#{artifact_id}",
        "getArtifact",
        "artifact",
        nil,
        &assert_ok_or_not_found/1,
        expected: [200, 404]
      )

  defp run_federation_setup(%{opts: %{include_federation: true}} = state) do
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

  defp run_federation_setup(state), do: state

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

  defp run_admin_storage(%{opts: %{include_admin: true}} = state) do
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
        %{"dryRun" => true, "backupBefore" => false},
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
            "dryRun" => true,
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
        %{"dryRun" => true},
        &assert_ok_or_expected_error/1,
        expected: [200, 422]
      )
    else
      state
    end
  end

  defp run_admin_storage(state), do: state

  defp run_post_measured_operations(%{opts: %{include_destructive: true}} = state) do
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

  defp run_post_measured_operations(state), do: state

  defp run_warmup(state) do
    if state.opts.warmup_iterations <= 0 do
      state
    else
      Enum.reduce(1..state.opts.warmup_iterations//1, state, fn _, acc ->
        run_steady_iteration(acc, measured?: false)
      end)
    end
  end

  defp run_measured(state) do
    window = start_window()
    iterations = measured_iterations(state.opts)
    deadline = measured_deadline(state.opts.duration_ms)

    measured_state =
      if state.opts.concurrency <= 1 do
        run_sequential_iterations(state, iterations, deadline)
      else
        run_concurrent_iterations(state, iterations, deadline)
      end

    measured_window =
      window
      |> end_window()
      |> Map.put("requestedDurationMs", state.opts.duration_ms)
      |> Map.put("minimumMeasuredDurationMs", state.opts.minimum_measured_duration)
      |> then(fn measured ->
        measured
        |> Map.put("durationSatisfied", measured_duration_satisfied?(state.opts, measured))
        |> Map.put("stopReason", measured_stop_reason(iterations, deadline, measured))
      end)

    put_in(measured_state, [:timing, "measured"], measured_window)
  end

  defp measured_iterations(%{iterations: nil, duration_ms: nil}), do: 1
  defp measured_iterations(%{iterations: nil}), do: nil
  defp measured_iterations(%{iterations: iterations}), do: max(iterations, 1)

  defp measured_deadline(nil), do: nil
  defp measured_deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp deadline_reached?(nil), do: false
  defp deadline_reached?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp run_sequential_iterations(state, nil, deadline) do
    if deadline_reached?(deadline),
      do: state,
      else: run_sequential_iterations(run_steady_iteration(state, measured?: true), nil, deadline)
  end

  defp run_sequential_iterations(state, iterations, deadline) do
    1..iterations
    |> Enum.reduce_while(state, fn _, acc ->
      if deadline_reached?(deadline),
        do: {:halt, acc},
        else: {:cont, run_steady_iteration(acc, measured?: true)}
    end)
  end

  defp run_concurrent_iterations(state, iterations, deadline) do
    do_run_concurrent_iterations(state, iterations, deadline, 0)
  end

  defp do_run_concurrent_iterations(state, iterations, deadline, completed) do
    if iteration_limit_reached?(iterations, completed) or deadline_reached?(deadline) do
      state
    else
      do_run_concurrent_batch(state, iterations, deadline, completed)
    end
  end

  defp do_run_concurrent_batch(state, iterations, deadline, completed) do
    batch_size =
      if is_nil(iterations),
        do: state.opts.concurrency,
        else: min(state.opts.concurrency, iterations - completed)

    state =
      1..batch_size
      |> Task.async_stream(
        fn _ -> run_steady_iteration(%{state | samples: [], assertions: []}, measured?: true) end,
        max_concurrency: state.opts.concurrency,
        timeout: :infinity
      )
      |> Enum.reduce(state, fn {:ok, partial}, acc ->
        %{
          acc
          | samples: acc.samples ++ partial.samples,
            assertions: acc.assertions ++ partial.assertions
        }
      end)

    do_run_concurrent_iterations(state, iterations, deadline, completed + batch_size)
  end

  defp iteration_limit_reached?(nil, _completed), do: false
  defp iteration_limit_reached?(iterations, completed), do: completed >= iterations

  defp measured_duration_satisfied?(opts, measured) do
    minimum = Map.get(opts, :minimum_measured_duration)

    if minimum do
      (measured["durationMs"] || 0) >= floor(minimum * 0.99)
    else
      true
    end
  end

  defp measured_stop_reason(iterations, deadline, measured) do
    cond do
      not is_nil(deadline) and (measured["endedAtMs"] || 0) >= deadline -> "duration_limit"
      is_nil(iterations) -> "completed"
      true -> "iteration_limit"
    end
  end

  defp run_steady_iteration(state, opts) do
    operations =
      state.opts.scenario
      |> EndpointMatrix.select(state.opts)
      |> Enum.filter(&implemented_operation?/1)

    operations =
      if operations == [] do
        EndpointMatrix.select("read_heavy", state.opts)
        |> Enum.filter(&implemented_operation?/1)
      else
        operations
      end

    operations =
      if state.opts.load_mode == "random" do
        Enum.shuffle(operations)
      else
        operations
      end

    Enum.reduce(operations, state, fn operation, acc ->
      run_operation(acc, operation, opts)
    end)
  end

  defp run_operation(state, %{"operationId" => "searchRepositoryFiles"}, opts) do
    repo = primary_repo(state)
    repo_id = repo.repo_id
    measured? = Keyword.fetch!(opts, :measured?)

    state
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/files/search",
      "searchRepositoryFiles",
      "repository_read",
      %{"paths" => ["docs/**", "plain/**"], "query" => "release", "limit" => 20},
      &assert_search_hits/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "readRepositoryFile"}, opts) do
    repo = primary_repo(state)
    repo_id = repo.repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)
    path = get_in(state.fixture.expected, [:known, :markdown_path]) || "docs/profiler-update.md"

    call!(
      state,
      :post,
      "/api/v1/repos/#{repo_id}/files/read",
      "readRepositoryFile",
      "repository_read",
      %{"ref" => ref, "path" => path, "parseFrontmatter" => true},
      &assert_ok/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "readRepositoryBlob"}, opts) do
    path = get_in(state.fixture.expected, [:known, :binary_path])
    measured? = Keyword.fetch!(opts, :measured?)

    if path do
      repo_id = repo_containing_path(state, path).repo_id

      call!(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/blobs/read",
        "readRepositoryBlob",
        "repository_read",
        %{"ref" => "refs/heads/main", "path" => path, "encoding" => "base64"},
        &assert_ok/1,
        measured?: measured?
      )
    else
      state
    end
  end

  defp run_operation(state, %{"operationId" => "listRepositoryPaths"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

    call!(
      state,
      :post,
      "/api/v1/repos/#{repo_id}/paths/list",
      "listRepositoryPaths",
      "repository_read",
      %{"ref" => ref, "paths" => ["docs/**"], "limit" => 50},
      &assert_ok/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "queryRepository"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

    call!(
      state,
      :post,
      "/api/v1/repos/#{repo_id}/query",
      "queryRepository",
      "repository_query",
      %{
        "ref" => ref,
        "type" => "combined",
        "query" => "release",
        "paths" => ["docs/**"],
        "limit" => 20
      },
      &assert_ok/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "federatedSearch"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

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
      &assert_ok_or_forbidden/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "federatedQuery"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

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
      &assert_ok_or_forbidden/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "federatedGraphQuery"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

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
      &assert_ok_or_forbidden/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "federatedContextBuild"}, opts) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    measured? = Keyword.fetch!(opts, :measured?)

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
      &assert_ok_or_forbidden/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "getWorkspaceStatus"}, opts) do
    measured? = Keyword.fetch!(opts, :measured?)

    call!(
      state,
      :get,
      "/api/v1/workspaces/#{state.workspace_id}/status",
      "getWorkspaceStatus",
      "workspace",
      nil,
      &assert_ok/1,
      measured?: measured?
    )
  end

  defp run_operation(state, %{"operationId" => "getWorkspaceDiff"}, opts) do
    measured? = Keyword.fetch!(opts, :measured?)

    call!(
      state,
      :get,
      "/api/v1/workspaces/#{state.workspace_id}/diff",
      "getWorkspaceDiff",
      "workspace",
      nil,
      &assert_ok/1,
      measured?: measured?
    )
  end

  defp run_operation(state, _operation, _opts), do: state

  defp implemented_operation?(%{"operationId" => operation_id}) do
    operation_id in [
      "searchRepositoryFiles",
      "readRepositoryFile",
      "readRepositoryBlob",
      "listRepositoryPaths",
      "queryRepository",
      "federatedSearch",
      "federatedQuery",
      "federatedGraphQuery",
      "federatedContextBuild",
      "getWorkspaceStatus",
      "getWorkspaceDiff"
    ]
  end

  defp build_report(state, started) do
    operations = Stats.aggregate(state.samples)
    assertions = assertion_summary(state.assertions)
    http_samples = measured_http_samples(state)

    coverage =
      EndpointMatrix.coverage(state.samples, state.opts, state[:covered_operation_ids] || [])

    summary = Stats.summary(state.samples, operations)
    throughput = Stats.throughput_breakdown(state.samples, http_samples, state.opts)
    model = ModelState.from_state(state)
    openapi_validation = OpenApiResponseValidator.report(state.assertions)

    report = %{
      "profile" => %{
        "id" => state.opts.profile_id,
        "generatedAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "startedAt" => DateTime.to_iso8601(started),
        "endedAt" => get_in(state, [:timing, "profile", "endedAt"]),
        "tool" => %{"name" => "treedb_profiler", "version" => TreeDbProfiler.version()}
      },
      "target" => %{"baseUrl" => state.opts.base_url},
      "environment" => SystemProfile.collect(),
      "timing" => timing_report(state),
      "workload" => %{
        "loadMode" => state.opts.load_mode,
        "fixture" => state.opts.fixture,
        "size" => state.opts.size,
        "scenario" => state.opts.scenario,
        "repoPrefix" => state.opts.repo_prefix,
        "portfolioRepoPrefix" => state.opts.portfolio_repo_prefix,
        "portfolioInitialRepos" => state.opts.portfolio_initial_repos,
        "portfolioMaxRepos" => state.opts.portfolio_max_repos,
        "portfolioGrowthTarget" => state.opts.portfolio_growth_target,
        "iterations" => state.opts.iterations,
        "iterationsExplicit" => state.opts.iterations_explicit,
        "durationMs" => state.opts.duration_ms,
        "durationIsControlling" => state.opts.duration_is_controlling,
        "minimumMeasuredDurationMs" => state.opts.minimum_measured_duration,
        "concurrency" => state.opts.concurrency,
        "warmupIterations" => state.opts.warmup_iterations,
        "reportFormat" => state.opts.report_format,
        "includeRequests" => state.opts.include_requests,
        "requestSampleLimit" => state.opts.request_sample_limit,
        "stateChecks" => state.opts.state_checks,
        "includeAdmin" => state.opts.include_admin,
        "includeDestructive" => state.opts.include_destructive,
        "includeExec" => state.opts.include_exec,
        "includeFederation" => state.opts.include_federation,
        "federationMode" => state.opts.federation_mode
      },
      "operationMix" => operation_mix_report(state.opts),
      "validation" => %{
        "semanticValidation" => state.opts.semantic_validation,
        "validationProbes" => state.opts.validation_probes,
        "validationProbeMode" => state.opts.validation_probe_mode,
        "probeSamplingRate" => state.opts.probe_sampling_rate,
        "strictQueryHitCounts" => state.opts.strict_query_hit_counts,
        "strictGraphExpectations" => state.opts.strict_graph_expectations,
        "strictSnapshotStability" => state.opts.strict_snapshot_stability,
        "reliabilityVerifier" => state.opts.reliability_verifier,
        "openapiResponseValidation" => state.opts.openapi_response_validation,
        "modelReconciliation" => state.opts.model_reconciliation
      },
      "fixtures" => fixture_report(state.fixture),
      "coverage" => coverage,
      "metrics" => %{
        "before" => state[:metrics_before] || %{},
        "after" => state[:metrics_after] || %{},
        "delta" => %{}
      },
      "operations" => operations,
      "categories" => Stats.category_aggregates(operations),
      "operationTypes" => Stats.operation_type_aggregates(operations),
      "throughput" => throughput,
      "resourceTuning" => resource_tuning_report(state),
      "serverRuntime" => server_runtime_report(state),
      "cache" => cache_report(state),
      "workerPools" => worker_pool_report(state),
      "saturation" => Stats.saturation_report(state.samples),
      "federationLoadBalancing" => federation_load_balancing_report(state),
      "portfolio" => state[:portfolio] || %{},
      "federation" => state[:federation] || %{"mode" => state.opts.federation_mode},
      "modelState" => ModelState.report(model),
      "reconciliation" => Reconciler.final_report(state, model),
      "operationChains" => OperationChain.report(state.samples, state.opts),
      "negativeTests" => NegativeRequestGenerator.report(state, state.opts),
      "metamorphic" => MetamorphicChecker.report(state.samples, state.opts),
      "delayedConsistency" => DelayedCheckScheduler.report(state.assertions, state.opts),
      "restartDurability" => RestartDurability.report(state.opts),
      "faultInjection" => FaultInjection.report(state.opts),
      "endpointConsistency" => EndpointConsistency.report(state.samples, state, state.opts),
      "openapiValidation" => openapi_validation,
      "replay" => ReplayLog.report(state.opts),
      "leakDetection" => LeakDetector.report(state),
      "permissionMatrix" => PermissionMatrix.report(state.samples, state.opts),
      "scheduler" => state[:scheduler] || %{},
      "validationProbes" => validation_probe_report(state.assertions, http_samples, state.opts),
      "concurrency" => concurrency_report(state[:portfolio_runtime], state.opts),
      "requestSamples" => state[:request_samples] || %{"failures" => [], "successes" => %{}},
      "errors" => error_report(state.samples),
      "assertions" => assertions,
      "summary" => summary
    }

    Map.put(report, "reliabilityBudget", ReliabilityBudget.evaluate(report, state.opts))
  end

  defp timing_report(state) do
    timing = state[:timing] || %{}

    %{
      "profile" => Map.get(timing, "profile", %{}),
      "setup" => Map.get(timing, "setup", %{}),
      "measured" =>
        Map.merge(
          %{
            "requestedDurationMs" => state.opts.duration_ms,
            "durationSatisfied" => is_nil(state.opts.duration_ms)
          },
          Map.get(timing, "measured", %{})
        ),
      "cleanup" => Map.get(timing, "cleanup", %{})
    }
  end

  defp error_report(samples) do
    errors = Enum.filter(samples, &(&1.ok != true and &1.assertion != :race_interference))

    %{
      "total" => length(errors),
      "byOperation" =>
        errors
        |> Enum.group_by(& &1.operation_id)
        |> Enum.map(fn {operation, values} -> {operation, length(values)} end)
        |> Map.new(),
      "samples" =>
        errors
        |> Enum.take(100)
        |> Enum.map(fn sample ->
          %{
            "operationId" => sample.operation_id,
            "status" => sample.status,
            "errorCode" => sample.error_code,
            "pathTemplate" => sample.path_template,
            "elapsedMs" => sample.duration_ms,
            "validation" => to_string(sample.assertion)
          }
        end)
    }
  end

  defp measured_http_samples(state) do
    samples = state[:http_samples] || state.samples
    measured = get_in(state, [:timing, "measured"]) || %{}
    started_at = measured["startedAt"]
    ended_at = measured["endedAt"]

    Enum.filter(samples, fn sample ->
      Map.get(sample, :counts_toward_total_http_rps, true) == true and
        Map.get(sample, :measured_window, :measured) == :measured and
        sample_in_measured_window?(sample, started_at, ended_at)
    end)
  end

  defp sample_in_measured_window?(_sample, nil, _ended_at), do: true
  defp sample_in_measured_window?(_sample, _started_at, nil), do: true

  defp sample_in_measured_window?(sample, started_at, ended_at) do
    with {:ok, sample_dt, _} <- DateTime.from_iso8601(sample.started_at),
         {:ok, start_dt, _} <- DateTime.from_iso8601(started_at),
         {:ok, end_dt, _} <- DateTime.from_iso8601(ended_at) do
      DateTime.compare(sample_dt, start_dt) != :lt and DateTime.compare(sample_dt, end_dt) != :gt
    else
      _ -> true
    end
  end

  defp validation_probe_report(samples_or_assertions, http_samples, opts)

  defp validation_probe_report(assertions, http_samples, opts) when is_list(assertions) do
    probe_samples =
      Enum.filter(http_samples, &(Map.get(&1, :sample_kind) == :validation_probe))

    total = Enum.sum(Enum.map(assertions, &(Map.get(&1, :validationProbes, 0) || 0)))
    total = max(total, length(probe_samples))

    failed =
      case probe_samples do
        [] ->
          assertions
          |> Enum.filter(&(Map.get(&1, :validationProbes, 0) > 0 and &1.passed == false))
          |> length()

        samples ->
          Enum.count(samples, &(&1.ok != true))
      end

    %{
      "total" => total,
      "failed" => failed,
      "samplingRate" => Map.get(opts, :probe_sampling_rate),
      "mode" => Map.get(opts, :validation_probe_mode),
      "samplesRetained" => length(probe_samples),
      "byOperation" =>
        assertions
        |> Enum.group_by(&operation_id_for/1)
        |> Enum.map(fn {operation, values} ->
          probes = Enum.sum(Enum.map(values, &(Map.get(&1, :validationProbes, 0) || 0)))

          failures =
            Enum.count(values, &(Map.get(&1, :validationProbes, 0) > 0 and &1.passed == false))

          {operation, %{"probes" => probes, "failed" => failures}}
        end)
        |> Map.new()
    }
  end

  defp federation_load_balancing_report(state) do
    counters =
      get_in(state, [:metrics_after, "counters"]) || get_in(state, [:metrics_after, :counters]) ||
        []

    spillovers = metric_sum(counters, "treedb_federation_read_spillover_total")
    failures = metric_sum(counters, "treedb_federation_read_spillover_failures_total")

    %{
      "enabled" =>
        System.get_env("TREEDB_FEDERATION_LOAD_AWARE_READS", "true") not in ["false", "0"],
      "readSpillovers" => spillovers,
      "failures" => failures,
      "byTargetNode" =>
        counters
        |> Enum.filter(
          &(Map.get(&1, :name) == "treedb_federation_read_spillover_total" or
              Map.get(&1, "name") == "treedb_federation_read_spillover_total")
        )
        |> Enum.reduce(%{}, fn counter, acc ->
          labels = Map.get(counter, :labels) || Map.get(counter, "labels") || %{}
          node = labels[:target_node] || labels["target_node"] || "unknown"
          Map.update(acc, node, counter_value(counter), &(&1 + counter_value(counter)))
        end)
    }
  end

  defp metric_sum(counters, name) do
    counters
    |> Enum.filter(&(Map.get(&1, :name) == name or Map.get(&1, "name") == name))
    |> Enum.map(&counter_value/1)
    |> Enum.sum()
  end

  defp counter_value(counter), do: Map.get(counter, :value) || Map.get(counter, "value") || 0

  defp operation_mix_report(opts) do
    %{
      "profilePurpose" => opts.profile_purpose,
      "performanceWorkload" => opts.performance_workload,
      "heavyOperationRate" => opts.heavy_operation_rate,
      "repoGrowthRate" => opts.repo_growth_rate,
      "snapshotRate" => opts.snapshot_rate,
      "graphRefreshRate" => opts.graph_refresh_rate,
      "importRate" => opts.import_rate,
      "rateLimited" => %{}
    }
  end

  defp resource_tuning_report(state) do
    cpu_budget = System.get_env("TREEDB_RUNTIME_CPU_BUDGET")
    memory_budget_mb = System.get_env("TREEDB_RUNTIME_MEMORY_BUDGET_MB")
    cache_fraction = System.get_env("TREEDB_CACHE_MEMORY_FRACTION") || "0.25"
    metrics = state[:metrics_after] || %{}

    memory_budget_mb =
      memory_budget_mb ||
        case metric_gauge(metrics, "treedb_runtime_memory_budget_bytes") do
          bytes when is_number(bytes) and bytes > 0 ->
            Integer.to_string(div(round(bytes), 1_048_576))

          _ ->
            nil
        end

    %{
      "cpuBudget" =>
        parse_int_or_nil(cpu_budget) || metric_gauge(metrics, "treedb_runtime_cpu_budget"),
      "memoryBudgetMb" => parse_int_or_nil(memory_budget_mb),
      "cacheMemoryFraction" => parse_float_or_nil(cache_fraction),
      "cacheBudgetMb" => cache_budget_mb(memory_budget_mb, cache_fraction),
      "cachePolicy" => if(memory_budget_mb in [nil, ""], do: "entry_count", else: "memory_budget")
    }
  end

  defp server_runtime_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["runtime"]) ||
      %{
        "beamMemoryBytes" => %{
          "total" => metric_gauge(metrics, "treedb_runtime_beam_memory_bytes"),
          "ets" => metric_gauge(metrics, "treedb_runtime_ets_memory_bytes"),
          "binary" => metric_gauge(metrics, "treedb_runtime_binary_memory_bytes"),
          "processes" => metric_gauge(metrics, "treedb_runtime_process_memory_bytes")
        },
        "memoryBudgetBytes" => metric_gauge(metrics, "treedb_runtime_memory_budget_bytes"),
        "cacheBudgetBytes" => metric_gauge(metrics, "treedb_runtime_cache_budget_bytes"),
        "cpuBudget" => metric_gauge(metrics, "treedb_runtime_cpu_budget")
      }
      |> reject_nil_deep()
  end

  defp cache_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["cache"]) ||
      metrics
      |> metric_entries("gauges", "treedb_cache_entries")
      |> Enum.reduce(%{}, fn entry, acc ->
        cache = cache_report_key(label(entry, "cache"))

        Map.put(acc, cache, %{
          "entries" => metric_value(entry),
          "approxBytes" => cache_metric(metrics, "treedb_cache_approx_bytes", cache),
          "hits" => cache_counter(metrics, "treedb_cache_hits_total", cache),
          "misses" => cache_counter(metrics, "treedb_cache_misses_total", cache),
          "evictions" => cache_counter(metrics, "treedb_cache_evictions_total", cache)
        })
      end)
  end

  defp worker_pool_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["workerPools"]) ||
      metrics
      |> metric_entries("gauges", "treedb_pool_size")
      |> Enum.reduce(%{}, fn entry, acc ->
        pool = pool_report_key(label(entry, "pool"))

        Map.put(acc, pool, %{
          "size" => metric_value(entry),
          "active" => pool_gauge(metrics, "treedb_pool_active", pool),
          "activeMax" => pool_gauge(metrics, "treedb_pool_active_max", pool),
          "queueDepth" => pool_gauge(metrics, "treedb_pool_queue_depth", pool),
          "queueDepthMax" => pool_gauge(metrics, "treedb_pool_queue_depth_max", pool),
          "queueMax" => pool_gauge(metrics, "treedb_pool_queue_max", pool),
          "pressure" => pressure_name(pool_gauge(metrics, "treedb_pool_pressure", pool)),
          "rejections" => pool_counter(metrics, "treedb_pool_rejections_total", pool),
          "queueTimeouts" => pool_counter(metrics, "treedb_pool_queue_timeouts_total", pool),
          "executionTimeouts" =>
            pool_counter(metrics, "treedb_pool_execution_timeouts_total", pool),
          "waitMs" => histogram_summary(metrics, "treedb_pool_wait_ms", pool),
          "executionMs" => histogram_summary(metrics, "treedb_pool_execution_ms", pool)
        })
      end)
  end

  defp metric_gauge(metrics, name), do: metric_value(find_metric(metrics, "gauges", name, %{}))

  defp pool_gauge(metrics, name, pool),
    do: metric_value(find_metric(metrics, "gauges", name, %{"pool" => pool_metric_key(pool)}))

  defp cache_metric(metrics, name, cache),
    do: metric_value(find_metric(metrics, "gauges", name, %{"cache" => cache_metric_key(cache)}))

  defp cache_counter(metrics, name, cache) do
    metrics
    |> metric_entries("counters", name)
    |> Enum.filter(&(label(&1, "cache") == cache_metric_key(cache)))
    |> Enum.map(&metric_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp pool_counter(metrics, name, pool) do
    metrics
    |> metric_entries("counters", name)
    |> Enum.filter(&(label(&1, "pool") == pool_metric_key(pool)))
    |> Enum.map(&metric_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp histogram_summary(metrics, name, pool) do
    case find_metric(metrics, "histograms", name, %{"pool" => pool_metric_key(pool)}) do
      nil ->
        %{}

      entry ->
        count = metric_field(entry, "count") || 0
        sum = metric_field(entry, "sum") || 0

        %{
          "count" => count,
          "mean" => if(count > 0, do: Float.round(sum / count, 3), else: nil)
        }
        |> reject_nil_deep()
    end
  end

  defp find_metric(metrics, kind, name, labels) do
    metrics
    |> metric_entries(kind, name)
    |> Enum.find(fn entry ->
      Enum.all?(labels, fn {key, value} -> label(entry, key) == value end)
    end)
  end

  defp metric_entries(metrics, kind, name) do
    metrics
    |> Map.get(kind, Map.get(metrics, String.to_atom(kind), []))
    |> Enum.filter(&(metric_field(&1, "name") == name))
  end

  defp metric_value(nil), do: nil
  defp metric_value(entry), do: metric_field(entry, "value")

  defp metric_field(entry, key), do: Map.get(entry, key) || Map.get(entry, String.to_atom(key))

  defp label(entry, key) do
    labels = metric_field(entry, "labels") || %{}
    Map.get(labels, key) || Map.get(labels, String.to_atom(key))
  end

  defp pool_report_key(pool), do: pool |> to_string() |> Macro.camelize() |> uncapitalize()
  defp pool_metric_key(pool), do: pool |> to_string() |> Macro.underscore()
  defp cache_report_key(cache), do: cache |> to_string() |> Macro.camelize() |> uncapitalize()
  defp cache_metric_key(cache), do: cache |> to_string() |> Macro.underscore()

  defp uncapitalize(<<first::binary-size(1), rest::binary>>),
    do: String.downcase(first) <> rest

  defp uncapitalize(other), do: other

  defp pressure_name(0), do: "low"
  defp pressure_name(1), do: "moderate"
  defp pressure_name(2), do: "high"
  defp pressure_name(3), do: "saturated"
  defp pressure_name(value), do: value

  defp reject_nil_deep(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        nested = reject_nil_deep(value)
        if nested == %{}, do: acc, else: Map.put(acc, key, nested)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp parse_float_or_nil(nil), do: nil
  defp parse_float_or_nil(""), do: nil

  defp parse_float_or_nil(value) do
    case Float.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp cache_budget_mb(nil, _fraction), do: nil
  defp cache_budget_mb("", _fraction), do: nil

  defp cache_budget_mb(memory_budget_mb, fraction) do
    with mb when is_integer(mb) <- parse_int_or_nil(memory_budget_mb),
         frac when is_float(frac) <- parse_float_or_nil(fraction) do
      Float.round(mb * frac, 1)
    else
      _ -> nil
    end
  end

  defp operation_id_for(assertion) do
    assertion[:operationId] || assertion[:operation_id] || assertion["operationId"] ||
      assertion["operation_id"] || "unknown"
  end

  defp concurrency_report(nil, opts) do
    %{
      "racePolicy" => opts.race_policy,
      "raceInterference" => %{
        "total" => 0,
        "verified" => 0,
        "unverified" => 0,
        "byOperation" => %{},
        "byCause" => %{},
        "samples" => []
      }
    }
  end

  defp concurrency_report(snapshot, opts) do
    races = Map.get(snapshot, :races, [])

    %{
      "racePolicy" => opts.race_policy,
      "raceInterference" => %{
        "total" => length(races),
        "verified" => Enum.count(races, &(Map.get(&1, :raceVerified) == true)),
        "unverified" => Enum.count(races, &(Map.get(&1, :raceVerified) != true)),
        "byOperation" => count_by(races, & &1.operationId),
        "byCause" => count_by(races, & &1.likelyCause),
        "samples" => Enum.take(races, 100)
      }
    }
  end

  defp count_by(values, fun) do
    values
    |> Enum.reduce(%{}, fn value, acc ->
      Map.update(acc, fun.(value) || "unknown", 1, &(&1 + 1))
    end)
  end

  defp call!(state, method, path, operation_id, category, body, assertion_fun, opts \\ []) do
    {state, _body} =
      call(state, method, path, operation_id, category, body,
        expected: Keyword.get(opts, :expected, 200),
        assert: assertion_fun,
        measured?: Keyword.get(opts, :measured?, true),
        headers: Keyword.get(opts, :headers, [])
      )

    state
  end

  defp call(state, method, path, operation_id, category, body, opts) do
    meta = %{
      operation_id: operation_id,
      path_template: template(path),
      category: category,
      scenario: state.opts.scenario,
      fixture: state.opts.fixture
    }

    req_opts =
      [method: method, path: path, headers: Keyword.get(opts, :headers, [])]
      |> put_payload(body)

    {sample, response} = HTTP.request(state.client, meta, req_opts)
    expected = List.wrap(Keyword.get(opts, :expected, 200))
    assertion_fun = Keyword.get(opts, :assert, &assert_ok/1)
    {assertion, assertion_error} = run_assertion(sample, response, expected, assertion_fun)
    openapi = openapi_result(state.opts, operation_id, sample, response)
    {assertion, assertion_error} = merge_openapi_assertion(assertion, assertion_error, openapi)

    sample =
      if assertion == :passed do
        %{sample | assertion: assertion, ok: true, error_code: nil}
      else
        %{
          sample
          | assertion: assertion,
            ok: false,
            error_code: sample.error_code || "assertion_failed"
        }
      end

    state =
      if Keyword.get(opts, :measured?, true) do
        update_in(state.samples, &(&1 ++ [sample]))
      else
        state
      end

    assertion_record = %{
      operationId: operation_id,
      path: path,
      pathTemplate: meta.path_template,
      fixture: state.opts.fixture,
      size: state.opts.size,
      rule: get_in(EndpointMatrix.operation_map(), [operation_id, "validation", "rule"]),
      openapiValidation: openapi,
      passed: assertion == :passed,
      error: assertion_error
    }

    ReplayLog.record(
      state.opts,
      %{
        id: nil,
        operation_id: operation_id,
        worker_id: nil,
        seed: state.opts.seed,
        expected_status: expected,
        body: body,
        precondition: %{}
      },
      sample,
      assertion_record
    )

    if assertion == :failed and state.opts.fail_fast do
      raise "profiler assertion failed for #{operation_id}: #{assertion_error}"
    end

    {update_in(state.assertions, &(&1 ++ [assertion_record])), response}
  end

  defp execute_profile_request(state, %ProfileRequest{} = request) do
    req_opts =
      [method: request.method, path: request.path, headers: request.headers || []]
      |> put_payload(request.body)

    {sample, response} =
      HTTP.request(
        state.client,
        ProfileRequest.to_meta(request, state.opts.scenario, state.opts.fixture),
        req_opts
      )

    {assertion, assertion_error, probe_samples, probe_failures} =
      run_profile_assertion(state, request, sample, response)

    openapi = openapi_result(state.opts, request.operation_id, sample, response)
    {assertion, assertion_error} = merge_openapi_assertion(assertion, assertion_error, openapi)

    sample =
      if assertion == :passed do
        %{
          sample
          | assertion: assertion,
            ok: true,
            error_code: nil
        }
      else
        %{
          sample
          | assertion: assertion,
            ok: false,
            error_code: sample.error_code || "assertion_failed"
        }
      end

    assertion_record = %{
      operationId: request.operation_id,
      requestId: request.id,
      path: request.path,
      pathTemplate: request.path_template,
      fixture: state.opts.fixture,
      size: state.opts.size,
      rule: request.validation_rule,
      semantic: state.opts.semantic_validation,
      validationProbes: length(probe_samples),
      validationProbeSamples: maybe_retain_probe_samples(state.opts, probe_samples),
      openapiValidation: openapi,
      passed: assertion == :passed,
      error: assertion_error
    }

    sample =
      if probe_failures == [] do
        sample
      else
        %{sample | assertion: :failed, ok: false, error_code: "validation_probe_failed"}
      end

    assertion_record =
      if probe_failures == [] do
        assertion_record
      else
        %{assertion_record | passed: false, error: Enum.join(probe_failures, "; ")}
      end

    if assertion_record.passed == false and state.opts.fail_fast do
      raise "profiler assertion failed for #{request.operation_id}: #{assertion_record.error}"
    end

    ReplayLog.record(state.opts, request, sample, replay_assertion_record(assertion_record))

    {sample, response, assertion_record}
  end

  defp openapi_result(opts, operation_id, sample, response) do
    case OpenApiResponseValidator.validate_response(operation_id, sample.status, response,
           enabled: opts.openapi_response_validation
         ) do
      :ok ->
        %{operationId: operation_id, status: sample.status, passed: true, message: nil}

      {:error, message} ->
        %{operationId: operation_id, status: sample.status, passed: false, message: message}
    end
  end

  defp merge_openapi_assertion(:passed, nil, %{passed: false, message: message}),
    do: {:failed, "OpenAPI response validation failed: #{message}"}

  defp merge_openapi_assertion(assertion, assertion_error, _openapi),
    do: {assertion, assertion_error}

  defp run_profile_assertion(state, request, sample, response) do
    cond do
      sample.status not in List.wrap(request.expected_status) ->
        {:failed, "expected status #{inspect(request.expected_status)}, got #{sample.status}", [],
         []}

      sample.status not in 200..299 ->
        {:failed, "non-success status #{sample.status} requires race classification", [], []}

      not state.opts.semantic_validation ->
        run_legacy_profile_assertion(response, request.validation_rule)

      true ->
        ctx = %{sample: sample, response: response, state: state, request: request}

        case Validation.validate(request.validation_rule, ctx) do
          :ok ->
            probes =
              if ProbePolicy.run_success_probes?(state.opts, request),
                do: ValidationProbe.run(state, request, response),
                else: %{samples: [], failures: []}

            if probes.failures == [] do
              {:passed, nil, probes.samples, []}
            else
              {:failed, Enum.join(probes.failures, "; "), probes.samples, probes.failures}
            end

          {:error, message} ->
            probes =
              if ProbePolicy.run_failure_probes?(state.opts, request),
                do: ValidationProbe.run(state, request, response),
                else: %{samples: [], failures: []}

            {:failed, message, probes.samples, probes.failures}
        end
    end
  end

  defp maybe_retain_probe_samples(_opts, probe_samples), do: probe_samples

  defp replay_assertion_record(%{validationProbeSamples: _} = assertion_record),
    do: Map.delete(assertion_record, :validationProbeSamples)

  defp replay_assertion_record(assertion_record), do: assertion_record

  defp run_legacy_profile_assertion(response, rule) do
    assertion_fun = assertion_for_rule(rule)

    try do
      assertion_fun.(response)
      {:passed, nil, [], []}
    rescue
      error -> {:failed, Exception.message(error), [], []}
    end
  end

  defp assertion_for_rule("search_hits_expected_terms"), do: &assert_search_hits/1
  defp assertion_for_rule("query_hits_expected_terms"), do: &assert_ok/1
  defp assertion_for_rule("graph_query_has_expected_shape"), do: &assert_ok/1
  defp assertion_for_rule("context_within_budget"), do: &assert_ok/1
  defp assertion_for_rule("snapshot_has_checksum"), do: &assert_ok/1
  defp assertion_for_rule("artifact_has_metadata"), do: &assert_ok/1
  defp assertion_for_rule(_), do: &assert_ok/1

  defp put_payload(opts, nil), do: opts
  defp put_payload(opts, body) when is_binary(body), do: Keyword.put(opts, :body, body)
  defp put_payload(opts, body), do: Keyword.put(opts, :json, body)

  defp run_assertion(sample, response, expected, assertion_fun) do
    cond do
      sample.status not in expected ->
        {:failed, "expected status #{inspect(expected)}, got #{sample.status}"}

      true ->
        try do
          assertion_fun.(response)
          {:passed, nil}
        rescue
          error -> {:failed, Exception.message(error)}
        end
    end
  end

  defp primary_repo(state), do: hd(state.fixture.local_repos)

  defp primary_node_id(%{opts: %{federation_mode: mode}}) when mode != "single_node", do: "node_a"
  defp primary_node_id(_state), do: "node_local"

  defp mirror_target_node_id(%{opts: %{federation_mode: "mirror_cluster"}}), do: "node_b"
  defp mirror_target_node_id(state), do: primary_node_id(state)

  defp repo_containing_path(state, path) do
    Enum.find(state.fixture.local_repos, primary_repo(state), fn repo ->
      Enum.any?(repo.files || [], &(&1.path == path))
    end)
  end

  defp replace_repo(repos, name, repo),
    do: Enum.map(repos, fn existing -> if existing.name == name, do: repo, else: existing end)

  defp fixture_report(fixture) do
    registered_by_name = Map.new(fixture.local_repos, &{&1.name, Map.has_key?(&1, :repo_id)})

    %{
      "families" =>
        Enum.map(fixture.families || [], fn family ->
          defn = family.definition

          %{
            "id" => family.fixture_id,
            "size" => family.size,
            "reposCreated" => length(family.repos),
            "reposRegistered" =>
              Enum.count(family.repos, &Map.get(registered_by_name, &1.name, false)),
            "files" => %{
              "markdown" => defn.markdown,
              "text" => defn.text,
              "json" => defn.json,
              "binary" => defn.binary
            },
            "history" => %{
              "branches" => defn.branches,
              "commits" => defn.commits
            },
            "graph" => %{
              "linksPerDoc" => defn.links_per_doc,
              "sectionsPerDoc" => defn.sections_per_doc
            }
          }
        end),
      "repos" => %{
        "created" => length(fixture.local_repos),
        "registered" => Enum.count(fixture.local_repos, &Map.has_key?(&1, :repo_id))
      },
      "files" => stringify_keys(fixture.expected.file_counts),
      "expected" => %{
        "searchTerms" => fixture.expected.search_hits,
        "graph" => %{
          "minNodes" => fixture.expected.graph.min_nodes,
          "minEdges" => fixture.expected.graph.min_edges,
          "expectedSections" => fixture.expected.graph.expected_sections,
          "expectedEntities" => fixture.expected.graph.expected_entities
        }
      }
    }
  end

  defp assertion_summary(assertions) do
    races = Enum.filter(assertions, &(Map.get(&1, :status) == :race_interference))
    failures = Enum.reject(assertions, &(&1.passed or Map.get(&1, :status) == :race_interference))

    %{
      "passed" => Enum.count(assertions, & &1.passed),
      "failed" => length(failures),
      "raceInterference" => length(races),
      "unavailable" => Enum.count(assertions, &(Map.get(&1, :status) == :unavailable)),
      "failures" => Enum.map(failures, &Map.new(&1))
    }
  end

  defp cleanup_fixture(%{opts: %{cleanup: true, keep_fixtures: false}, fixture: %{root: root}}) do
    File.rm_rf(root)
    :ok
  end

  defp cleanup_fixture(_state), do: :ok

  defp template(path) do
    path
    |> String.replace(~r/repo_[A-Za-z0-9_-]+/, "{repo_id}")
    |> String.replace(~r/ws_[A-Za-z0-9_-]+/, "{workspace_id}")
    |> String.replace(~r/snap_[A-Za-z0-9_-]+/, "{snapshot_id}")
    |> String.replace(~r/artifact_[A-Za-z0-9_-]+/, "{artifact_id}")
    |> String.replace(~r/\?.*$/, "")
  end

  defp stringify_keys(map), do: map |> Enum.map(fn {k, v} -> {to_string(k), v} end) |> Map.new()

  defp assert_ok(%{"ok" => true}), do: :ok
  defp assert_ok(%{"status" => "ok"}), do: :ok
  defp assert_ok(_payload), do: raise("expected ok response")

  defp assert_ok_or_unavailable(%{"ok" => false, "error" => %{"code" => "service_unavailable"}}),
    do: :ok

  defp assert_ok_or_unavailable(payload), do: assert_ok(payload)

  defp assert_ok_or_not_found(%{"ok" => false, "error" => %{"code" => "not_found"}}), do: :ok
  defp assert_ok_or_not_found(payload), do: assert_ok(payload)

  defp assert_ok_or_forbidden(%{"ok" => false, "error" => %{"code" => "permission_denied"}}),
    do: :ok

  defp assert_ok_or_forbidden(payload), do: assert_ok(payload)

  defp assert_ok_or_validation(%{"ok" => false, "error" => %{"code" => "validation_error"}}),
    do: :ok

  defp assert_ok_or_validation(payload), do: assert_ok(payload)

  defp assert_ok_or_expected_error(%{"ok" => false, "error" => %{"code" => code}})
       when code in [
              "conflict",
              "validation_error",
              "permission_denied",
              "unsupported_transport",
              "sandbox_unavailable",
              "sandbox_policy_denied",
              "not_found"
            ],
       do: :ok

  defp assert_ok_or_expected_error(payload), do: assert_ok(payload)

  defp assert_binary_or_ok(binary) when is_binary(binary), do: :ok
  defp assert_binary_or_ok(payload), do: assert_ok(payload)

  defp assert_search_hits(payload) do
    assert_ok(payload)
    results = payload["results"] || get_in(payload, ["search", "results"]) || []
    if length(results) <= 0, do: raise("expected search results")
  end

  defp assert_path(payload, path) do
    assert_ok(payload)
    actual = get_in(payload, ["file", "path"]) || get_in(payload, ["blob", "path"])
    if actual != path, do: raise("expected path #{path}, got #{inspect(actual)}")
  end

  defp assert_truthy(nil, label), do: raise("expected #{label}")
  defp assert_truthy("", label), do: raise("expected #{label}")
  defp assert_truthy(_, _), do: :ok
end
