defmodule TreeDxProfiler.PortfolioState do
  @moduledoc false

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def snapshot(pid), do: GenServer.call(pid, :snapshot)
  def next_counter(pid, key), do: GenServer.call(pid, {:next_counter, key})
  def choose_repo(pid), do: GenServer.call(pid, :choose_repo)
  def choose_mutable_repo(pid), do: GenServer.call(pid, :choose_mutable_repo)
  def reserve_workspace_repo(pid), do: GenServer.call(pid, :reserve_workspace_repo)
  def choose_workspace(pid), do: GenServer.call(pid, :choose_workspace)
  def reserve_workspace(pid), do: GenServer.call(pid, :reserve_workspace)
  def choose_workspace_file(pid), do: GenServer.call(pid, :choose_workspace_file)
  def reserve_workspace_file(pid), do: GenServer.call(pid, :reserve_workspace_file)
  def choose_dirty_workspace(pid), do: GenServer.call(pid, :choose_dirty_workspace)
  def reserve_dirty_workspace(pid), do: GenServer.call(pid, :reserve_dirty_workspace)
  def choose_readable_path(pid), do: GenServer.call(pid, :choose_readable_path)

  def choose_readable_path(pid, repo_id),
    do: GenServer.call(pid, {:choose_readable_path, repo_id})

  def choose_binary_path(pid), do: GenServer.call(pid, :choose_binary_path)
  def choose_artifact(pid), do: GenServer.call(pid, :choose_artifact)
  def choose_graph_repo(pid), do: GenServer.call(pid, :choose_graph_repo)
  def reserve_graph_refresh_repo(pid), do: GenServer.call(pid, :reserve_graph_refresh_repo)
  def reserve_snapshot_repo(pid), do: GenServer.call(pid, :reserve_snapshot_repo)
  def can_create_repo?(pid), do: GenServer.call(pid, :can_create_repo?)
  def deletion_candidate(pid), do: GenServer.call(pid, :deletion_candidate)
  def snapshot_for_request(pid, target), do: GenServer.call(pid, {:snapshot_for_request, target})

  def classify_state_change(pid, request),
    do: GenServer.call(pid, {:classify_state_change, request})

  def apply_effect(pid, effect), do: GenServer.call(pid, {:apply_effect, effect, nil, nil})

  def apply_effect(pid, effect, request_id, response_status),
    do: GenServer.call(pid, {:apply_effect, effect, request_id, response_status})

  def record_race(pid, race), do: GenServer.cast(pid, {:record_race, race})

  def record_assertion_failure(pid, failure),
    do: GenServer.cast(pid, {:record_assertion_failure, failure})

  def record_failure(pid), do: GenServer.cast(pid, :record_failure)

  @impl true
  def init(opts) do
    now = System.monotonic_time(:millisecond)

    repos =
      opts.fixture.local_repos
      |> Enum.with_index(1)
      |> Enum.map(fn {repo, index} ->
        TreeDxProfiler.PortfolioNormalization.normalize(repo, index, now)
      end)

    {:ok,
     %{
       opts: opts,
       started_at_ms: now,
       repos: repos,
       active_workspaces: %{},
       closed_workspaces: 0,
       artifacts: [],
       snapshots: [],
       graph_ready_repos: MapSet.new(),
       graph_refreshing_repos: MapSet.new(),
       committing_repos: MapSet.new(),
       workspace_creating_repos: MapSet.new(),
       mutating_workspaces: MapSet.new(),
       snapshotting_repos: MapSet.new(),
       races: [],
       assertion_failures: [],
       counters: %{
         repo: length(repos),
         request: 0,
         file: 0,
         blob: 0,
         workspace: 0,
         created_repos: length(repos),
         deleted_repos: 0,
         files_generated: 0,
         files_deleted: 0,
         blobs_generated: 0,
         snapshots_built: 0,
         artifacts_exported: 0,
         commits_created: 0,
         errors: 0,
         assertions: 0,
         race_interference: 0
       }
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, public_snapshot(state), state}

  def handle_call({:next_counter, key}, _from, state) do
    next = Map.get(state.counters, key, 0) + 1
    {:reply, next, put_in(state, [:counters, key], next)}
  end

  def handle_call(:choose_repo, _from, state),
    do: {:reply, Enum.random(active_repos(state)), state}

  def handle_call(:choose_mutable_repo, _from, state) do
    repo =
      state
      |> mutable_repos()
      |> random_or_nil()

    {:reply, repo, state}
  end

  def handle_call(:reserve_workspace_repo, _from, state) do
    repo =
      state
      |> mutable_repos()
      |> Enum.reject(&MapSet.member?(state.workspace_creating_repos, &1.repo_id))
      |> random_or_nil()

    if repo do
      state = update_in(state.workspace_creating_repos, &MapSet.put(&1, repo.repo_id))
      {:reply, repo, state}
    else
      {:reply, nil, state}
    end
  end

  def handle_call(:choose_workspace, _from, state) do
    workspace =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&mutable_workspace?(state, &1))
      |> random_or_nil()

    {:reply, workspace, state}
  end

  def handle_call(:reserve_workspace, _from, state) do
    workspace =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&mutable_workspace?(state, &1))
      |> random_or_nil()

    if workspace do
      state = update_in(state.mutating_workspaces, &MapSet.put(&1, workspace.workspace_id))
      {:reply, workspace, state}
    else
      {:reply, nil, state}
    end
  end

  def handle_call(:choose_workspace_file, _from, state) do
    candidate =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&mutable_workspace?(state, &1))
      |> Enum.flat_map(fn workspace ->
        workspace.written_files
        |> Map.values()
        |> Enum.map(&{workspace, &1})
      end)
      |> random_or_nil()

    {:reply, candidate, state}
  end

  def handle_call(:reserve_workspace_file, _from, state) do
    candidate =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&mutable_workspace?(state, &1))
      |> Enum.flat_map(fn workspace ->
        workspace.written_files
        |> Map.values()
        |> Enum.map(&{workspace, &1})
      end)
      |> random_or_nil()

    case candidate do
      {workspace, _file} ->
        state = update_in(state.mutating_workspaces, &MapSet.put(&1, workspace.workspace_id))
        {:reply, candidate, state}

      nil ->
        {:reply, nil, state}
    end
  end

  def handle_call(:choose_dirty_workspace, _from, state) do
    workspace =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&dirty_workspace?(state, &1))
      |> random_or_nil()

    {:reply, workspace, state}
  end

  def handle_call(:reserve_dirty_workspace, _from, state) do
    workspace =
      state.active_workspaces
      |> Map.values()
      |> Enum.filter(&dirty_workspace?(state, &1))
      |> random_or_nil()

    if workspace do
      state =
        state
        |> TreeDxProfiler.PortfolioEffects.update_workspace(
          workspace.workspace_id,
          &Map.put(&1, :committing?, true)
        )
        |> update_in([:committing_repos], &MapSet.put(&1, workspace.repo_id))

      {:reply, workspace, state}
    else
      {:reply, nil, state}
    end
  end

  def handle_call(:choose_readable_path, _from, state) do
    path =
      state
      |> active_repos()
      |> Enum.flat_map(& &1.readable_paths)
      |> random_or_nil()

    {:reply, path, state}
  end

  def handle_call({:choose_readable_path, repo_id}, _from, state) do
    path =
      state
      |> active_repos()
      |> Enum.find(&(&1.repo_id == repo_id))
      |> case do
        nil -> nil
        repo -> random_or_nil(repo.readable_paths)
      end

    {:reply, path, state}
  end

  def handle_call(:choose_binary_path, _from, state) do
    path =
      state
      |> active_repos()
      |> Enum.flat_map(& &1.binary_paths)
      |> random_or_nil()

    {:reply, path, state}
  end

  def handle_call(:choose_artifact, _from, state),
    do: {:reply, random_or_nil(state.artifacts), state}

  def handle_call(:choose_graph_repo, _from, state) do
    repo =
      state
      |> active_repos()
      |> Enum.filter(
        &(MapSet.member?(state.graph_ready_repos, &1.repo_id) and
            not MapSet.member?(state.graph_refreshing_repos, &1.repo_id))
      )
      |> random_or_nil()

    {:reply, repo, state}
  end

  def handle_call(:reserve_graph_refresh_repo, _from, state) do
    repo =
      state
      |> mutable_repos()
      |> Enum.reject(&MapSet.member?(state.graph_refreshing_repos, &1.repo_id))
      |> random_or_nil()

    if repo do
      state = update_in(state.graph_refreshing_repos, &MapSet.put(&1, repo.repo_id))
      {:reply, repo, state}
    else
      {:reply, nil, state}
    end
  end

  def handle_call(:reserve_snapshot_repo, _from, state) do
    repo =
      state
      |> mutable_repos()
      |> Enum.reject(&MapSet.member?(state.graph_refreshing_repos, &1.repo_id))
      |> Enum.reject(&MapSet.member?(state.snapshotting_repos, &1.repo_id))
      |> random_or_nil()

    if repo do
      state = update_in(state.snapshotting_repos, &MapSet.put(&1, repo.repo_id))
      {:reply, repo, state}
    else
      {:reply, nil, state}
    end
  end

  def handle_call(:can_create_repo?, _from, state) do
    max_repos = state.opts.portfolio_max_repos
    {:reply, length(active_repos(state)) < max_repos, state}
  end

  def handle_call(:deletion_candidate, _from, state) do
    min_age = state.opts.portfolio_min_repo_age_before_delete || 0
    now = System.monotonic_time(:millisecond)

    candidate =
      state
      |> active_repos()
      |> Enum.reject(&repo_has_active_workspace?(state, &1.repo_id))
      |> Enum.filter(&(now - &1.created_at_ms >= min_age))
      |> case do
        [_only] -> nil
        repos when length(repos) > 1 -> Enum.random(repos)
        _ -> nil
      end

    {:reply, candidate, state}
  end

  def handle_call({:snapshot_for_request, target}, _from, state) do
    {:reply, request_snapshot(state, target || %{}), state}
  end

  def handle_call({:classify_state_change, request}, _from, state) do
    {:reply, request_snapshot(state, request.target || %{}), state}
  end

  def handle_call({:apply_effect, nil, _request_id, _response_status}, _from, state),
    do: {:reply, :ok, state}

  def handle_call({:apply_effect, effect, request_id, response_status}, _from, state) do
    {:reply, :ok,
     TreeDxProfiler.PortfolioEffects.apply(state, effect, request_id, response_status)}
  end

  @impl true
  def handle_cast(:record_failure, state),
    do: {:noreply, update_in(state, [:counters, :errors], &(&1 + 1))}

  def handle_cast({:record_race, race}, state) do
    {:noreply,
     state
     |> update_in([:races], &[race | &1])
     |> update_in([:counters, :race_interference], &(&1 + 1))}
  end

  def handle_cast({:record_assertion_failure, failure}, state) do
    {:noreply, update_in(state.assertion_failures, &[failure | &1])}
  end

  def portfolio_fixture(opts, repo_index),
    do: TreeDxProfiler.PortfolioFixture.build(opts, repo_index)

  defp public_snapshot(state) do
    %{
      repos: active_repos(state),
      active_workspaces: Map.values(state.active_workspaces),
      artifacts: state.artifacts,
      snapshots: state.snapshots,
      counters: state.counters,
      races: Enum.reverse(state.races),
      assertion_failures: Enum.reverse(state.assertion_failures),
      final: %{
        "initialRepos" => Map.get(state.opts, :portfolio_initial_repos, length(state.repos)),
        "finalRepos" => length(active_repos(state)),
        "createdRepos" => state.counters.created_repos,
        "deletedRepos" => state.counters.deleted_repos,
        "activeWorkspaces" => map_size(state.active_workspaces),
        "closedWorkspaces" => state.closed_workspaces,
        "filesGenerated" => state.counters.files_generated,
        "filesDeleted" => state.counters.files_deleted,
        "blobsGenerated" => state.counters.blobs_generated,
        "snapshotsBuilt" => state.counters.snapshots_built,
        "artifactsExported" => state.counters.artifacts_exported,
        "commitsCreated" => state.counters.commits_created
      }
    }
  end

  defp active_repos(state), do: Enum.reject(state.repos, & &1.deleted?)

  defp mutable_repos(state) do
    state
    |> active_repos()
    |> Enum.reject(&MapSet.member?(state.committing_repos, &1.repo_id))
    |> Enum.reject(&MapSet.member?(state.workspace_creating_repos, &1.repo_id))
    |> Enum.reject(&MapSet.member?(state.snapshotting_repos, &1.repo_id))
  end

  defp repo_has_active_workspace?(state, repo_id) do
    state.active_workspaces
    |> Map.values()
    |> Enum.any?(&(&1.repo_id == repo_id))
  end

  defp random_or_nil([]), do: nil
  defp random_or_nil(values), do: Enum.random(values)

  defp dirty_workspace?(_state, nil), do: false

  defp dirty_workspace?(state, workspace) do
    Map.get(workspace, :pending_changes, 0) > 0 and
      mutable_workspace?(state, workspace)
  end

  defp mutable_workspace?(_state, nil), do: false

  defp mutable_workspace?(state, workspace) do
    not Map.get(workspace, :committing?, false) and
      Map.get(workspace, :open?, true) and
      not MapSet.member?(state.mutating_workspaces, workspace.workspace_id) and
      not MapSet.member?(state.committing_repos, workspace.repo_id) and
      not MapSet.member?(state.snapshotting_repos, workspace.repo_id)
  end

  defp request_snapshot(state, target) do
    repo_id = target[:repo_id] || target["repo_id"] || target["repoId"]
    workspace_id = target[:workspace_id] || target["workspace_id"] || target["workspaceId"]

    repo = Enum.find(state.repos, &(&1.repo_id == repo_id))

    workspace =
      cond do
        is_binary(workspace_id) ->
          Map.get(state.active_workspaces, workspace_id) ||
            get_in(state, [:closed_workspace_records, workspace_id])

        true ->
          nil
      end

    %{
      repo_generation: repo && repo.generation,
      repo_deleted?: repo && repo.deleted?,
      repo_last_request_id: repo && (repo.deleted_by_request_id || repo.created_by_request_id),
      workspace_generation: workspace && workspace.generation,
      workspace_open?: if(workspace, do: Map.get(workspace, :open?, true), else: nil),
      workspace_pending_changes: workspace && workspace.pending_changes,
      workspace_last_mutation_request_id: workspace && workspace.last_mutation_request_id,
      workspace_closed_by_request_id: workspace && workspace.closed_by_request_id
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
