defmodule TreeDbProfiler.Scheduler do
  @moduledoc false

  alias TreeDbProfiler.{PortfolioState, ProfileRequest, RequestGenerator, Sampler}

  def run(state, portfolio_pid, opts, execute_fun) do
    deadline = if opts.duration_ms, do: System.monotonic_time(:millisecond) + opts.duration_ms
    iterations = max(opts.iterations, 1)
    counter = :counters.new(1, [:atomics])

    initial = %{
      samples: [],
      assertions: [],
      sampler: Sampler.new(opts.request_sample_limit),
      worker_count: opts.concurrency,
      started_at_ms: System.monotonic_time(:millisecond),
      ended_at_ms: nil
    }

    workers = for worker <- 1..opts.concurrency, do: worker

    result =
      workers
      |> Task.async_stream(
        fn worker_id ->
          worker_loop(
            worker_id,
            state,
            portfolio_pid,
            opts,
            execute_fun,
            counter,
            iterations,
            deadline
          )
        end,
        max_concurrency: opts.concurrency,
        timeout: :infinity
      )
      |> Enum.reduce(initial, fn
        {:ok, partial}, acc -> merge_partial(acc, partial)
        {:exit, reason}, acc -> record_worker_exit(acc, reason)
      end)

    %{result | ended_at_ms: System.monotonic_time(:millisecond)}
  end

  defp worker_loop(
         worker_id,
         state,
         portfolio_pid,
         opts,
         execute_fun,
         counter,
         iterations,
         deadline
       ) do
    do_worker_loop(%{
      worker_id: worker_id,
      state: state,
      portfolio_pid: portfolio_pid,
      opts: opts,
      execute_fun: execute_fun,
      counter: counter,
      iterations: iterations,
      deadline: deadline,
      samples: [],
      assertions: [],
      sampler: Sampler.new(opts.request_sample_limit)
    })
  end

  defp do_worker_loop(ctx) do
    cond do
      stop_for_duration?(ctx.deadline) ->
        Map.take(ctx, [:samples, :assertions, :sampler])

      not claim_iteration(ctx.counter, ctx.iterations) ->
        Map.take(ctx, [:samples, :assertions, :sampler])

      true ->
        request = RequestGenerator.next(ctx.portfolio_pid, ctx.opts)
        {sample, response, assertion} = ctx.execute_fun.(ctx.state, request)
        apply_successful_effect(ctx.portfolio_pid, request, response, assertion)

        do_worker_loop(%{
          ctx
          | samples: [sample | ctx.samples],
            assertions: [assertion | ctx.assertions],
            sampler: Sampler.add(ctx.sampler, sample)
        })
    end
  end

  defp stop_for_duration?(nil), do: false
  defp stop_for_duration?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp claim_iteration(counter, iterations) do
    :counters.add(counter, 1, 1)
    :counters.get(counter, 1) <= iterations
  end

  defp apply_successful_effect(portfolio_pid, %ProfileRequest{} = request, response, assertion) do
    if assertion.passed do
      request.state_effect
      |> enrich_effect(response)
      |> then(&PortfolioState.apply_effect(portfolio_pid, &1))
    else
      PortfolioState.apply_effect(portfolio_pid, request.failure_effect)
      PortfolioState.record_failure(portfolio_pid)
    end
  end

  defp enrich_effect(%{kind: :repo_registered} = effect, response) do
    Map.put(effect, :repo_id, get_in(response, ["repo", "repoId"]))
  end

  defp enrich_effect(%{kind: :workspace_created} = effect, response) do
    Map.put(
      effect,
      :workspace_id,
      response["workspaceId"] || get_in(response, ["workspace", "workspaceId"])
    )
  end

  defp enrich_effect(%{kind: :snapshot_built} = effect, response) do
    Map.put(effect, :snapshot_id, get_in(response, ["snapshot", "snapshotId"]))
  end

  defp enrich_effect(%{kind: :artifact_exported} = effect, response) do
    Map.put(effect, :artifact_id, get_in(response, ["artifact", "artifactId"]))
  end

  defp enrich_effect(effect, _response), do: effect

  defp merge_partial(acc, partial) do
    %{
      acc
      | samples: acc.samples ++ Enum.reverse(partial.samples),
        assertions: acc.assertions ++ Enum.reverse(partial.assertions),
        sampler: merge_sampler(acc.sampler, partial.sampler)
    }
  end

  defp merge_sampler(left, right) do
    %{
      left
      | failures: left.failures ++ right.failures,
        successes:
          Map.merge(left.successes, right.successes, fn _operation, a, b ->
            Enum.take(a ++ b, left.limit)
          end)
    }
  end

  defp record_worker_exit(acc, reason) do
    sample = %{
      operation_id: "profilerWorker",
      method: "INTERNAL",
      path_template: "profiler_worker",
      path: "profiler_worker",
      category: "profiler",
      scenario: "portfolio",
      fixture: "portfolio",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      duration_ms: 0.0,
      status: 0,
      ok: false,
      error_code: "worker_exit",
      request_bytes: 0,
      response_bytes: byte_size(inspect(reason)),
      assertion: :failed
    }

    assertion = %{
      operationId: "profilerWorker",
      path: "profiler_worker",
      pathTemplate: "profiler_worker",
      fixture: "portfolio",
      size: "runtime",
      rule: "worker_completed",
      passed: false,
      error: inspect(reason)
    }

    %{acc | samples: [sample | acc.samples], assertions: [assertion | acc.assertions]}
  end
end
