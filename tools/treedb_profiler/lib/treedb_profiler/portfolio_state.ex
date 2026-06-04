defmodule TreeDbProfiler.PortfolioState do
  @moduledoc false

  use GenServer

  alias TreeDbProfiler.DataGenerator

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def snapshot(pid), do: GenServer.call(pid, :snapshot)
  def next_counter(pid, key), do: GenServer.call(pid, {:next_counter, key})
  def choose_repo(pid), do: GenServer.call(pid, :choose_repo)
  def choose_mutable_repo(pid), do: GenServer.call(pid, :choose_mutable_repo)
  def reserve_workspace_repo(pid), do: GenServer.call(pid, :reserve_workspace_repo)
  def choose_workspace(pid), do: GenServer.call(pid, :choose_workspace)
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
  def apply_effect(pid, effect), do: GenServer.call(pid, {:apply_effect, effect})
  def record_failure(pid), do: GenServer.cast(pid, :record_failure)

  @impl true
  def init(opts) do
    now = System.monotonic_time(:millisecond)

    repos =
      opts.fixture.local_repos
      |> Enum.with_index(1)
      |> Enum.map(fn {repo, index} -> normalize_repo(repo, index, now) end)

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
       snapshotting_repos: MapSet.new(),
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
         assertions: 0
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
        |> update_workspace(workspace.workspace_id, &Map.put(&1, :committing?, true))
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

  def handle_call({:apply_effect, nil}, _from, state), do: {:reply, :ok, state}

  def handle_call({:apply_effect, effect}, _from, state) do
    {:reply, :ok, apply_state_effect(state, effect)}
  end

  @impl true
  def handle_cast(:record_failure, state),
    do: {:noreply, update_in(state, [:counters, :errors], &(&1 + 1))}

  def portfolio_fixture(opts, repo_index) do
    defn = TreeDbProfiler.Fixtures.definition("small-docs", opts.size)
    name = DataGenerator.repo_name(opts.portfolio_repo_prefix, opts.profile_id, repo_index)

    %{
      family: "portfolio",
      size: opts.size,
      name: name,
      markdown: max(div(defn.markdown, 2), 4),
      text: max(div(defn.text, 2), 1),
      json: max(div(defn.json, 2), 1),
      binary: max(div(defn.binary, 2), 0),
      blob_sizes: defn.blob_sizes,
      branches: max(defn.branches, 1),
      commits: max(defn.commits, 2),
      tags: 1,
      links_per_doc: max(defn.links_per_doc, 1),
      sections_per_doc: max(defn.sections_per_doc, 2),
      search_terms: defn.search_terms,
      protected_paths: defn.protected_paths,
      workspace_writes: max(defn.workspace_writes, 2),
      workspace_patches: max(defn.workspace_patches, 1),
      workspace_deletes: max(defn.workspace_deletes, 1),
      repo_index: repo_index
    }
  end

  defp apply_state_effect(state, %{kind: :repo_registered, repo: repo, repo_id: repo_id}) do
    index = length(state.repos) + 1

    normalized =
      repo
      |> Map.put(:repo_id, repo_id)
      |> normalize_repo(index, System.monotonic_time(:millisecond))

    state
    |> update_in([:repos], &(&1 ++ [normalized]))
    |> update_in([:counters, :created_repos], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :workspace_created, workspace_id: ws, repo_id: repo_id}) do
    workspace = %{
      workspace_id: ws,
      repo_id: repo_id,
      pending_changes: 0,
      created_at_ms: System.monotonic_time(:millisecond)
    }

    state
    |> release_workspace_creation(repo_id)
    |> put_in([:active_workspaces, ws], workspace)
    |> update_in([:counters, :workspace], &(&1 + 1))
  end

  defp apply_state_effect(state, %{
         kind: :file_written,
         workspace_id: ws,
         path: path,
         content: content
       }) do
    state
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.update(:pending_changes, 1, &(&1 + 1))
      |> Map.update(:written_paths, [path], &[path | &1])
      |> Map.update(
        :written_files,
        [%{path: path, sha256: DataGenerator.sha256(content), content: content}],
        &[%{path: path, sha256: DataGenerator.sha256(content), content: content} | &1]
      )
    end)
    |> update_in([:counters, :files_generated], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :file_deleted, workspace_id: ws, path: path}) do
    state
    |> update_workspace(ws, &Map.update(&1, :pending_changes, 1, fn value -> value + 1 end))
    |> update_in([:counters, :files_deleted], &(&1 + 1))
    |> remove_repo_path(ws, path)
  end

  defp apply_state_effect(state, %{
         kind: :blob_written,
         workspace_id: ws,
         path: path,
         sha256: sha256
       }) do
    state
    |> update_workspace(ws, &Map.update(&1, :pending_changes, 1, fn value -> value + 1 end))
    |> add_repo_binary_path(ws, path, sha256)
    |> update_in([:counters, :blobs_generated], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :workspace_committed, workspace_id: ws}) do
    workspace = Map.get(state.active_workspaces, ws)

    state
    |> release_workspace_commit(workspace)
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.put(:pending_changes, 0)
      |> Map.put(:committing?, false)
    end)
    |> update_in([:counters, :commits_created], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :workspace_closed, workspace_id: ws}) do
    {workspace, active} = Map.pop(state.active_workspaces, ws)

    state
    |> Map.put(:active_workspaces, active)
    |> update_in([:counters, :closed_workspaces], &((&1 || 0) + if(workspace, do: 1, else: 0)))
    |> update_in([:closed_workspaces], &(&1 + if(workspace, do: 1, else: 0)))
  end

  defp apply_state_effect(state, %{kind: :snapshot_built, snapshot_id: id, repo_id: repo_id})
       when is_binary(id) do
    state
    |> update_in([:snapshots], &[%{snapshot_id: id, repo_id: repo_id} | &1])
    |> update_in([:snapshotting_repos], &MapSet.delete(&1, repo_id))
    |> update_in([:counters, :snapshots_built], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :artifact_exported, artifact_id: id, repo_id: repo_id})
       when is_binary(id) do
    state
    |> update_in([:artifacts], &[%{artifact_id: id, repo_id: repo_id} | &1])
    |> update_in([:counters, :artifacts_exported], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :repo_deleted, repo_id: repo_id}) do
    state
    |> update_in([:repos], fn repos ->
      Enum.map(repos, fn repo ->
        if repo.repo_id == repo_id, do: Map.put(repo, :deleted?, true), else: repo
      end)
    end)
    |> update_in([:counters, :deleted_repos], &(&1 + 1))
  end

  defp apply_state_effect(state, %{kind: :graph_refreshed, repo_id: repo_id}) do
    state
    |> update_in([:graph_ready_repos], &MapSet.put(&1, repo_id))
    |> update_in([:graph_refreshing_repos], &MapSet.delete(&1, repo_id))
  end

  defp apply_state_effect(state, %{kind: :workspace_commit_finished, workspace_id: ws}) do
    workspace = Map.get(state.active_workspaces, ws)

    state
    |> release_workspace_commit(workspace)
    |> update_workspace(ws, &Map.put(&1, :committing?, false))
  end

  defp apply_state_effect(state, %{kind: :workspace_create_finished, repo_id: repo_id}) do
    release_workspace_creation(state, repo_id)
  end

  defp apply_state_effect(state, %{kind: :graph_refresh_finished, repo_id: repo_id}) do
    update_in(state.graph_refreshing_repos, &MapSet.delete(&1, repo_id))
  end

  defp apply_state_effect(state, %{kind: :snapshot_finished, repo_id: repo_id}) do
    update_in(state.snapshotting_repos, &MapSet.delete(&1, repo_id))
  end

  defp apply_state_effect(state, _effect), do: state

  defp normalize_repo(repo, index, now) do
    files = repo[:files] || []

    %{
      index: index,
      name: repo.name,
      path: repo.path,
      repo_id: repo[:repo_id],
      created_at_ms: now,
      deleted?: false,
      default_ref: repo[:default_ref] || "refs/heads/main",
      readable_paths:
        files
        |> Enum.filter(
          &(&1.kind in ["markdown", "text", "json", "workspace_write", "workspace_patch"])
        )
        |> Enum.map(&%{path: &1.path, sha256: &1.sha256, content: &1[:content]}),
      binary_paths:
        files
        |> Enum.filter(&(&1.kind == "binary"))
        |> Enum.map(&%{path: &1.path, sha256: &1.sha256, byte_length: &1.byte_length})
    }
  end

  defp public_snapshot(state) do
    %{
      repos: active_repos(state),
      active_workspaces: Map.values(state.active_workspaces),
      artifacts: state.artifacts,
      snapshots: state.snapshots,
      counters: state.counters,
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

  defp update_workspace(state, ws, fun) do
    update_in(state.active_workspaces, fn workspaces ->
      if Map.has_key?(workspaces, ws) do
        Map.update!(workspaces, ws, fun)
      else
        workspaces
      end
    end)
  end

  defp add_repo_binary_path(state, ws, path, sha256) do
    add_repo_path(state, ws, :binary_paths, %{path: path, sha256: sha256})
  end

  defp release_workspace_commit(state, nil), do: state

  defp release_workspace_commit(state, workspace) do
    update_in(state.committing_repos, &MapSet.delete(&1, workspace.repo_id))
  end

  defp release_workspace_creation(state, nil), do: state

  defp release_workspace_creation(state, repo_id) do
    update_in(state.workspace_creating_repos, &MapSet.delete(&1, repo_id))
  end

  defp add_repo_path(state, ws, key, value) do
    repo_id = get_in(state.active_workspaces, [ws, :repo_id])

    update_in(state.repos, fn repos ->
      Enum.map(repos, fn repo ->
        if repo.repo_id == repo_id, do: Map.update(repo, key, [value], &[value | &1]), else: repo
      end)
    end)
  end

  defp remove_repo_path(state, ws, path) do
    repo_id = get_in(state.active_workspaces, [ws, :repo_id])

    update_in(state.repos, fn repos ->
      Enum.map(repos, fn repo ->
        if repo.repo_id == repo_id do
          Map.update(
            repo,
            :readable_paths,
            [],
            &Enum.reject(&1, fn file -> file.path == path end)
          )
        else
          repo
        end
      end)
    end)
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
      not MapSet.member?(state.committing_repos, workspace.repo_id) and
      not MapSet.member?(state.snapshotting_repos, workspace.repo_id)
  end
end
