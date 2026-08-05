defmodule TreeDxProfiler.Scheduler do
  @moduledoc false

  alias TreeDxProfiler.{PortfolioState, ProfileRequest, RaceClassifier, RequestGenerator, Sampler}

  def run(state, portfolio_pid, opts, execute_fun) do
    started_at = DateTime.utc_now()
    started_at_ms = System.monotonic_time(:millisecond)
    deadline = if opts.duration_ms, do: started_at_ms + opts.duration_ms
    iterations = effective_iterations(opts)
    counter = :counters.new(1, [:atomics])
    pacer = :atomics.new(1, [])

    initial = %{
      samples: [],
      http_samples: [],
      assertions: [],
      sampler: Sampler.new(opts.request_sample_limit),
      worker_count: opts.concurrency,
      started_at: DateTime.to_iso8601(started_at),
      started_at_ms: started_at_ms,
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
            pacer,
            iterations,
            deadline,
            started_at_ms
          )
        end,
        max_concurrency: opts.concurrency,
        timeout: :infinity
      )
      |> Enum.reduce(initial, fn
        {:ok, partial}, acc -> merge_partial(acc, partial)
        {:exit, reason}, acc -> record_worker_exit(acc, reason)
      end)

    ended_at = DateTime.utc_now()
    ended_at_ms = System.monotonic_time(:millisecond)
    duration_ms = ended_at_ms - started_at_ms

    result
    |> Map.put(:ended_at, DateTime.to_iso8601(ended_at))
    |> Map.put(:ended_at_ms, ended_at_ms)
    |> Map.put(:duration_ms, duration_ms)
    |> Map.put(:requested_duration_ms, opts.duration_ms)
    |> Map.put(:minimum_measured_duration_ms, Map.get(opts, :minimum_measured_duration))
    |> Map.put(:stop_reason, stop_reason(counter, iterations, deadline, ended_at_ms))
    |> Map.put(:duration_satisfied, duration_satisfied?(opts, duration_ms))
  end

  defp effective_iterations(%{iterations: nil, duration_ms: nil}), do: 1
  defp effective_iterations(%{iterations: nil}), do: nil
  defp effective_iterations(%{iterations: iterations}), do: max(iterations, 1)

  defp worker_loop(
         worker_id,
         state,
         portfolio_pid,
         opts,
         execute_fun,
         counter,
         pacer,
         iterations,
         deadline,
         started_at_ms
       ) do
    do_worker_loop(%{
      worker_id: worker_id,
      state: state,
      portfolio_pid: portfolio_pid,
      opts: opts,
      execute_fun: execute_fun,
      counter: counter,
      pacer: pacer,
      iterations: iterations,
      deadline: deadline,
      started_at_ms: started_at_ms,
      samples: [],
      http_samples: [],
      assertions: [],
      sampler: Sampler.new(opts.request_sample_limit)
    })
  end

  defp do_worker_loop(ctx) do
    cond do
      stop_for_duration?(ctx.deadline) ->
        Map.take(ctx, [:samples, :http_samples, :assertions, :sampler])

      not claim_iteration(ctx.counter, ctx.iterations) ->
        Map.take(ctx, [:samples, :http_samples, :assertions, :sampler])

      true ->
        run_claimed_request(ctx)
    end
  end

  defp run_claimed_request(ctx) do
    if pace(ctx) == :stop do
      Map.take(ctx, [:samples, :http_samples, :assertions, :sampler])
    else
      request =
        ctx.portfolio_pid
        |> RequestGenerator.next(ctx.opts)
        |> attach_runtime_context(ctx.portfolio_pid, ctx.worker_id)

      {sample, response, assertion} = ctx.execute_fun.(ctx.state, request)

      {sample, assertion} =
        classify_and_apply(ctx.portfolio_pid, request, response, sample, assertion, ctx)

      do_worker_loop(%{
        ctx
        | samples: [sample | ctx.samples],
          http_samples: http_samples_for(sample, assertion) ++ ctx.http_samples,
          assertions: [assertion | ctx.assertions],
          sampler: Sampler.add(ctx.sampler, sample)
      })
    end
  end

  defp pace(%{opts: %{target_primary_rps: target}} = ctx)
       when is_number(target) and target > 0 do
    slot = claim_current_slot(ctx.pacer, ctx.started_at_ms, target)
    due_at = ctx.started_at_ms + floor(slot * 1000 / target)

    if not is_nil(ctx.deadline) and due_at >= ctx.deadline do
      wait_until(ctx.deadline)
      :stop
    else
      wait_until(due_at)
      if stop_for_duration?(ctx.deadline), do: :stop, else: :ready
    end
  end

  defp pace(_ctx), do: :ready

  defp claim_current_slot(pacer, started_at_ms, target) do
    elapsed_ms = max(System.monotonic_time(:millisecond) - started_at_ms, 0)
    elapsed_slot = floor(elapsed_ms * target / 1000)
    current = :atomics.get(pacer, 1)
    slot = max(current, elapsed_slot)

    case :atomics.compare_exchange(pacer, 1, current, slot + 1) do
      :ok -> slot
      _changed -> claim_current_slot(pacer, started_at_ms, target)
    end
  end

  defp wait_until(monotonic_ms) do
    wait_ms = monotonic_ms - System.monotonic_time(:millisecond)
    if wait_ms > 0, do: Process.sleep(wait_ms)
  end

  defp stop_for_duration?(nil), do: false
  defp stop_for_duration?(deadline), do: System.monotonic_time(:millisecond) >= deadline

  defp claim_iteration(_counter, nil), do: true

  defp claim_iteration(counter, iterations) do
    :counters.add(counter, 1, 1)
    :counters.get(counter, 1) <= iterations
  end

  defp stop_reason(counter, iterations, deadline, ended_at_ms) do
    cond do
      not is_nil(deadline) and ended_at_ms >= deadline -> "duration_limit"
      not is_nil(iterations) and :counters.get(counter, 1) > iterations -> "iteration_limit"
      true -> "completed"
    end
  end

  defp duration_satisfied?(opts, duration_ms) do
    minimum = Map.get(opts, :minimum_measured_duration)

    if minimum do
      duration_ms >= floor(minimum * 0.99)
    else
      true
    end
  end

  defp attach_runtime_context(%ProfileRequest{} = request, portfolio_pid, worker_id) do
    request = Map.put(request, :worker_id, worker_id)

    if stateful_request?(request) do
      %{
        request
        | precondition: PortfolioState.snapshot_for_request(portfolio_pid, request.target)
      }
    else
      request
    end
  rescue
    _ -> request
  end

  defp classify_and_apply(portfolio_pid, request, response, sample, assertion, ctx) do
    classification =
      if assertion.passed do
        {:ok, :not_race}
      else
        current_state = PortfolioState.snapshot_for_request(portfolio_pid, request.target)

        RaceClassifier.classify(%{
          request: request,
          sample: sample,
          response: response,
          precondition: request.precondition,
          current_state: current_state,
          validation_error: assertion.error,
          worker_id: ctx.worker_id
        })
        |> RaceClassifier.apply_policy(ctx.opts.race_policy)
      end

    case classification do
      {:race, race} ->
        PortfolioState.record_race(portfolio_pid, race)

        PortfolioState.apply_effect(
          portfolio_pid,
          request.failure_effect,
          request.id,
          sample.status
        )

        {%{sample | assertion: :race_interference, ok: true, error_code: nil},
         race_assertion(assertion, race)}

      {:passed, race} when is_map(race) ->
        PortfolioState.record_race(portfolio_pid, race)
        apply_successful_effect(portfolio_pid, request, response, sample)

        {%{sample | assertion: :passed, ok: true, error_code: nil},
         %{assertion | passed: true, race: race, error: nil}}

      {:failed, race} when is_map(race) ->
        PortfolioState.record_race(portfolio_pid, race)
        PortfolioState.record_assertion_failure(portfolio_pid, assertion)

        PortfolioState.apply_effect(
          portfolio_pid,
          request.failure_effect,
          request.id,
          sample.status
        )

        {%{
           sample
           | assertion: :failed,
             ok: false,
             error_code: sample.error_code || "race_interference_failed"
         }, %{assertion | passed: false, race: race, error: race.likelyCause}}

      _ ->
        if assertion.passed do
          apply_successful_effect(portfolio_pid, request, response, sample)
          {sample, assertion}
        else
          PortfolioState.apply_effect(
            portfolio_pid,
            request.failure_effect,
            request.id,
            sample.status
          )

          PortfolioState.record_failure(portfolio_pid)
          PortfolioState.record_assertion_failure(portfolio_pid, assertion)
          {sample, assertion}
        end
    end
  end

  defp apply_successful_effect(portfolio_pid, %ProfileRequest{} = request, response, sample) do
    effect =
      Map.get(request.state_effect_on_status || %{}, sample.status) ||
        if(sample.status in 200..299, do: request.state_effect)

    if effect do
      effect
      |> enrich_effect(response)
      |> then(&PortfolioState.apply_effect(portfolio_pid, &1, request.id, sample.status))
    end
  end

  defp stateful_request?(request) do
    request.state_effect != nil or request.failure_effect != nil or
      map_size(request.state_effect_on_status || %{}) > 0 or
      map_size(request.race_context || %{}) > 0
  end

  defp race_assertion(assertion, race) do
    assertion
    |> Map.put(:passed, true)
    |> Map.put(:status, :race_interference)
    |> Map.put(:race, race)
    |> Map.put(:error, nil)
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
        http_samples: acc.http_samples ++ Enum.reverse(partial.http_samples),
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

    %{
      acc
      | samples: [sample | acc.samples],
        http_samples: [sample | acc.http_samples],
        assertions: [assertion | acc.assertions]
    }
  end

  defp http_samples_for(primary_sample, assertion) do
    probe_samples = Map.get(assertion, :validationProbeSamples, []) || []
    [primary_sample | probe_samples]
  end
end
