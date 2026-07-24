defmodule TreeDxProfiler.PortfolioEffects do
  @moduledoc false

  alias TreeDxProfiler.DataGenerator

  def apply(state, effect, request_id, response_status)
  def apply(state, nil, _request_id, _response_status), do: state

  def apply(
        state,
        %{kind: :repo_registered, repo: repo, repo_id: repo_id},
        request_id,
        _status
      ) do
    index = length(state.repos) + 1

    normalized =
      repo
      |> Map.put(:repo_id, repo_id)
      |> Map.put(:created_by_request_id, request_id)
      |> TreeDxProfiler.PortfolioNormalization.normalize(
        index,
        System.monotonic_time(:millisecond)
      )

    state
    |> update_in([:repos], &(&1 ++ [normalized]))
    |> update_in([:counters, :created_repos], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :workspace_created, workspace_id: ws, repo_id: repo_id},
        request_id,
        _status
      ) do
    workspace = %{
      workspace_id: ws,
      repo_id: repo_id,
      generation: 0,
      open?: true,
      pending_changes: 0,
      written_files: %{},
      deleted_paths: MapSet.new(),
      created_by_request_id: request_id,
      closed_by_request_id: nil,
      last_mutation_request_id: nil,
      created_at_ms: System.monotonic_time(:millisecond)
    }

    state
    |> release_workspace_creation(repo_id)
    |> put_in([:active_workspaces, ws], workspace)
    |> update_in([:counters, :workspace], &(&1 + 1))
  end

  def apply(
        state,
        %{
          kind: :file_written,
          workspace_id: ws,
          path: path,
          content: content
        },
        request_id,
        _status
      ) do
    expectation = %{path: path, sha256: DataGenerator.sha256(content), content: content}

    state
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.update(:generation, 1, &(&1 + 1))
      |> Map.update(:pending_changes, 1, &(&1 + 1))
      |> Map.update(:written_paths, [path], &[path | &1])
      |> Map.update(:written_files, %{path => expectation}, &Map.put(&1, path, expectation))
      |> Map.update(:deleted_paths, MapSet.new(), &MapSet.delete(&1, path))
      |> Map.put(:last_mutation_request_id, request_id)
    end)
    |> release_workspace_mutation(ws)
    |> update_in([:counters, :files_generated], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :file_deleted, workspace_id: ws, path: path},
        request_id,
        _status
      ) do
    state
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.update(:generation, 1, &(&1 + 1))
      |> Map.update(:pending_changes, 1, fn value -> value + 1 end)
      |> Map.update(:deleted_paths, MapSet.new([path]), &MapSet.put(&1, path))
      |> Map.update(:written_files, %{}, &Map.delete(&1, path))
      |> Map.put(:last_mutation_request_id, request_id)
    end)
    |> release_workspace_mutation(ws)
    |> update_in([:counters, :files_deleted], &(&1 + 1))
    |> remove_repo_path(ws, path)
  end

  def apply(
        state,
        %{
          kind: :blob_written,
          workspace_id: ws,
          path: path,
          sha256: sha256
        },
        request_id,
        _status
      ) do
    state
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.update(:generation, 1, &(&1 + 1))
      |> Map.update(:pending_changes, 1, fn value -> value + 1 end)
      |> Map.put(:last_mutation_request_id, request_id)
    end)
    |> release_workspace_mutation(ws)
    |> add_repo_binary_path(ws, path, sha256)
    |> update_in([:counters, :blobs_generated], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :workspace_committed, workspace_id: ws},
        request_id,
        _status
      ) do
    workspace = Map.get(state.active_workspaces, ws)

    state
    |> release_workspace_commit(workspace)
    |> release_workspace_mutation(ws)
    |> update_workspace(ws, fn workspace ->
      workspace
      |> Map.update(:generation, 1, &(&1 + 1))
      |> Map.put(:pending_changes, 0)
      |> Map.put(:committing?, false)
      |> Map.put(:last_mutation_request_id, request_id)
    end)
    |> update_in([:counters, :commits_created], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :workspace_closed, workspace_id: ws},
        request_id,
        _status
      ) do
    {workspace, active} = Map.pop(state.active_workspaces, ws)

    closed_workspace =
      if workspace do
        workspace
        |> Map.put(:open?, false)
        |> Map.put(:closed_by_request_id, request_id)
      end

    state
    |> Map.put(:active_workspaces, active)
    |> release_workspace_mutation(ws)
    |> then(fn state ->
      if closed_workspace do
        Map.update(
          state,
          :closed_workspace_records,
          %{ws => closed_workspace},
          &Map.put(&1, ws, closed_workspace)
        )
      else
        state
      end
    end)
    |> update_in([:counters, :closed_workspaces], &((&1 || 0) + if(workspace, do: 1, else: 0)))
    |> update_in([:closed_workspaces], &(&1 + if(workspace, do: 1, else: 0)))
  end

  def apply(
        state,
        %{kind: :snapshot_built, snapshot_id: id, repo_id: repo_id},
        _request_id,
        _status
      )
      when is_binary(id) do
    state
    |> update_in([:snapshots], &[%{snapshot_id: id, repo_id: repo_id} | &1])
    |> update_in([:snapshotting_repos], &MapSet.delete(&1, repo_id))
    |> update_in([:counters, :snapshots_built], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :artifact_exported, artifact_id: id, repo_id: repo_id},
        _request_id,
        _status
      )
      when is_binary(id) do
    state
    |> update_in([:artifacts], &[%{artifact_id: id, repo_id: repo_id} | &1])
    |> update_in([:counters, :artifacts_exported], &(&1 + 1))
  end

  def apply(state, %{kind: :repo_deleted, repo_id: repo_id}, request_id, _status) do
    state
    |> update_in([:repos], fn repos ->
      Enum.map(repos, fn repo ->
        if repo.repo_id == repo_id,
          do:
            repo
            |> Map.put(:deleted?, true)
            |> Map.put(:deleted_by_request_id, request_id)
            |> Map.update(:generation, 1, &(&1 + 1)),
          else: repo
      end)
    end)
    |> update_in([:counters, :deleted_repos], &(&1 + 1))
  end

  def apply(
        state,
        %{kind: :graph_refreshed, repo_id: repo_id},
        _request_id,
        _status
      ) do
    state
    |> update_in([:graph_ready_repos], &MapSet.put(&1, repo_id))
    |> update_in([:graph_refreshing_repos], &MapSet.delete(&1, repo_id))
  end

  def apply(
        state,
        %{kind: :workspace_mutation_finished, workspace_id: ws},
        _request_id,
        _status
      ) do
    release_workspace_mutation(state, ws)
  end

  def apply(
        state,
        %{kind: :workspace_commit_finished, workspace_id: ws},
        _request_id,
        _status
      ) do
    workspace = Map.get(state.active_workspaces, ws)

    state
    |> release_workspace_commit(workspace)
    |> release_workspace_mutation(ws)
    |> update_workspace(ws, &Map.put(&1, :committing?, false))
  end

  def apply(
        state,
        %{kind: :workspace_create_finished, repo_id: repo_id},
        _request_id,
        _status
      ) do
    release_workspace_creation(state, repo_id)
  end

  def apply(
        state,
        %{kind: :graph_refresh_finished, repo_id: repo_id},
        _request_id,
        _status
      ) do
    update_in(state.graph_refreshing_repos, &MapSet.delete(&1, repo_id))
  end

  def apply(
        state,
        %{kind: :snapshot_finished, repo_id: repo_id},
        _request_id,
        _status
      ) do
    update_in(state.snapshotting_repos, &MapSet.delete(&1, repo_id))
  end

  def apply(state, _effect, _request_id, _status), do: state

  def update_workspace(state, ws, fun) do
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

  defp release_workspace_mutation(state, nil), do: state

  defp release_workspace_mutation(state, workspace_id) do
    update_in(state.mutating_workspaces, &MapSet.delete(&1, workspace_id))
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
end
