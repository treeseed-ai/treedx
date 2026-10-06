defmodule TreeDxProfiler.ScenarioRunner do
  @moduledoc false

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_binary_or_ok: 1,
      assert_ok: 1,
      assert_ok_or_unavailable: 1,
      call: 7,
      call!: 7,
      execute_profile_request: 2
    ]

  alias TreeDxProfiler.{
    FederationScenario,
    Fixtures,
    HTTP,
    PortfolioState,
    Sampler,
    Scheduler
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

    report = TreeDxProfiler.ScenarioReport.build(final_state, started)
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
      request = TreeDxProfiler.RequestGenerator.build(:create_repository, portfolio_pid, acc.opts)
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

  defp register_repos(state), do: TreeDxProfiler.ScenarioRepositorySetup.register_repos(state)
  defp configure_repo(state), do: TreeDxProfiler.ScenarioRepositorySetup.configure_repo(state)
  defp create_workspace(state), do: TreeDxProfiler.ScenarioRepositorySetup.create_workspace(state)
  defp mutate_workspace(state), do: TreeDxProfiler.ScenarioWorkspaceSetup.mutate_workspace(state)

  defp refresh_graph_and_index(state),
    do: TreeDxProfiler.ScenarioGraphSetup.refresh_graph_and_index(state)

  defp build_snapshot_artifact(state),
    do: TreeDxProfiler.ScenarioGraphSetup.build_snapshot_artifact(state)

  defp run_federation_setup(state),
    do: TreeDxProfiler.ScenarioSetupExtensions.run_federation_setup(state)

  defp run_admin_storage(state),
    do: TreeDxProfiler.ScenarioSetupExtensions.run_admin_storage(state)

  defp run_post_measured_operations(state),
    do: TreeDxProfiler.ScenarioSetupExtensions.run_post_measured_operations(state)

  defp run_warmup(state), do: TreeDxProfiler.ScenarioMeasured.run_warmup(state)
  defp run_measured(state), do: TreeDxProfiler.ScenarioMeasured.run_measured(state)

  defp primary_repo(state), do: hd(state.fixture.local_repos)

  defp cleanup_fixture(%{opts: %{cleanup: true, keep_fixtures: false}, fixture: %{root: root}}) do
    File.rm_rf(root)
    :ok
  end

  defp cleanup_fixture(_state), do: :ok
end
