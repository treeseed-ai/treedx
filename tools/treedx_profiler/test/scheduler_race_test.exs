defmodule TreeDxProfiler.SchedulerRaceTest do
  use ExUnit.Case

  alias TreeDxProfiler.{Fixtures, PortfolioState, Scheduler}

  test "does not apply file write effect for unverified accepted race status" do
    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "scheduler-race",
        repo_prefix: "profile-",
        fixture_root: Path.join(System.tmp_dir!(), "treedx-profiler-test"),
        size: "small",
        seed: "scheduler-race"
      )
      |> then(fn fixture ->
        repos =
          fixture.local_repos
          |> Enum.with_index(1)
          |> Enum.map(fn {repo, index} -> Map.put(repo, :repo_id, "repo_#{index}") end)

        %{fixture | local_repos: repos}
      end)

    {:ok, pid} =
      PortfolioState.start_link(%{
        fixture: fixture,
        size: "small",
        portfolio_max_repos: 10,
        portfolio_min_repo_age_before_delete: 0
      })

    repo = PortfolioState.choose_repo(pid)

    PortfolioState.apply_effect(
      pid,
      %{kind: :workspace_created, workspace_id: "ws_race", repo_id: repo.repo_id},
      "setup",
      200
    )

    opts = %{
      iterations: 100,
      iterations_explicit: true,
      duration_ms: nil,
      minimum_measured_duration: nil,
      concurrency: 1,
      request_sample_limit: 10,
      race_policy: "separate",
      portfolio_create_weight: 0,
      portfolio_delete_weight: 0,
      portfolio_growth_target: "steady",
      include_destructive: false,
      profile_id: "scheduler-race",
      semantic_validation: true,
      validation_probes: false,
      max_validation_probes_per_request: 3,
      validation_probe_timeout_ms: 30_000
    }

    result =
      Scheduler.run(%{}, pid, opts, fn _state, request ->
        sample = %{
          operation_id: request.operation_id,
          method: "PUT",
          path_template: request.path_template,
          path: request.path,
          category: request.category,
          scenario: "portfolio",
          fixture: "small-docs",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          duration_ms: 1.0,
          status: 409,
          ok: false,
          error_code: "conflict",
          request_bytes: 0,
          response_bytes: 0,
          assertion: :failed
        }

        assertion = %{
          operationId: request.operation_id,
          path: request.path,
          pathTemplate: request.path_template,
          fixture: "small-docs",
          size: "small",
          rule: request.validation_rule,
          passed: false,
          error: "conflict"
        }

        {sample, %{"ok" => false, "error" => %{"code" => "conflict"}}, assertion}
      end)

    assert Enum.any?(result.samples, &(&1.assertion == :failed))
    refute Enum.any?(result.samples, &(&1.assertion == :race_interference))
    snapshot = PortfolioState.snapshot(pid)
    workspace = Enum.find(snapshot.active_workspaces, &(&1.workspace_id == "ws_race"))
    assert workspace.pending_changes == 0
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "treedx-profiler-test"))
  end
end
