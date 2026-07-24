defmodule TreeDxProfiler.ScenarioMeasured do
  @moduledoc false

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_ok: 1,
      assert_ok_or_forbidden: 1,
      assert_search_hits: 1,
      call!: 8
    ]

  alias TreeDxProfiler.EndpointMatrix

  def run_warmup(state) do
    if state.opts.warmup_iterations <= 0 do
      state
    else
      Enum.reduce(1..state.opts.warmup_iterations//1, state, fn _, acc ->
        run_steady_iteration(acc, measured?: false)
      end)
    end
  end

  def run_measured(state) do
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

  defp primary_repo(state), do: hd(state.fixture.local_repos)

  defp repo_containing_path(state, path) do
    Enum.find(state.fixture.local_repos, primary_repo(state), fn repo ->
      Enum.any?(repo.files, &(&1.path == path))
    end)
  end
end
