defmodule TreeDxProfiler.SchedulerTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{Fixtures, PortfolioState, Scheduler}

  test "runs concurrent worker loops until iteration limit" do
    root =
      Path.join(
        System.tmp_dir!(),
        "treedx-profiler-scheduler-#{System.unique_integer([:positive])}"
      )

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "scheduler-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "scheduler-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "scheduler-test",
      scenario: "full_api",
      fixture_root: root,
      size: "small",
      iterations: 5,
      iterations_explicit: true,
      duration_ms: nil,
      minimum_measured_duration: nil,
      concurrency: 3,
      request_sample_limit: 2,
      portfolio_max_repos: 10,
      portfolio_create_weight: 0,
      portfolio_delete_weight: 0,
      portfolio_growth_target: "steady",
      portfolio_repo_prefix: "profile-",
      include_destructive: false
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_1",
      repo_id: "repo_seed"
    })

    state = %{opts: opts, client: nil}

    result =
      Scheduler.run(state, pid, opts, fn _state, request ->
        sample = %{
          operation_id: request.operation_id,
          method: String.upcase(to_string(request.method)),
          path_template: request.path_template,
          path: request.path,
          category: request.category,
          scenario: "full_api",
          fixture: "small-docs",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          duration_ms: 1.0,
          status: 200,
          ok: true,
          error_code: nil,
          request_bytes: 1,
          response_bytes: 1,
          assertion: :passed
        }

        response = %{
          "ok" => true,
          "workspaceId" => "ws_new",
          "snapshot" => %{"snapshotId" => "snap_1"},
          "artifact" => %{"artifactId" => "artifact_1"}
        }

        assertion = %{
          operationId: request.operation_id,
          path: request.path,
          pathTemplate: request.path_template,
          fixture: "small-docs",
          size: "small",
          rule: request.validation_rule,
          passed: true,
          error: nil
        }

        {sample, response, assertion}
      end)

    assert length(result.samples) == 5
    assert result.worker_count == 3
    assert result.stop_reason == "iteration_limit"
    File.rm_rf!(root)
  end

  test "duration-controlled scheduler ignores missing iteration cap" do
    root =
      Path.join(
        System.tmp_dir!(),
        "treedx-profiler-scheduler-duration-#{System.unique_integer([:positive])}"
      )

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "scheduler-duration-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "scheduler-duration-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "scheduler-duration-test",
      scenario: "full_api",
      fixture_root: root,
      size: "small",
      iterations: nil,
      iterations_explicit: false,
      duration_ms: 40,
      minimum_measured_duration: 20,
      concurrency: 2,
      request_sample_limit: 2,
      portfolio_max_repos: 10,
      portfolio_create_weight: 0,
      portfolio_delete_weight: 0,
      portfolio_growth_target: "steady",
      portfolio_repo_prefix: "profile-",
      include_destructive: false,
      race_policy: "separate"
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_1",
      repo_id: "repo_seed"
    })

    result =
      Scheduler.run(%{opts: opts, client: nil}, pid, opts, fn _state, request ->
        Process.sleep(5)

        sample = %{
          operation_id: request.operation_id,
          method: String.upcase(to_string(request.method)),
          path_template: request.path_template,
          path: request.path,
          category: request.category,
          scenario: "full_api",
          fixture: "small-docs",
          started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          duration_ms: 1.0,
          status: 200,
          ok: true,
          error_code: nil,
          request_bytes: 1,
          response_bytes: 1,
          assertion: :passed
        }

        assertion = %{
          operationId: request.operation_id,
          path: request.path,
          pathTemplate: request.path_template,
          fixture: "small-docs",
          size: "small",
          rule: request.validation_rule,
          passed: true,
          error: nil
        }

        {sample, %{"ok" => true}, assertion}
      end)

    assert length(result.samples) > 1
    assert result.stop_reason == "duration_limit"
    assert result.duration_satisfied
    File.rm_rf!(root)
  end
end
