defmodule TreeDxProfiler.ModelState do
  @moduledoc false

  def from_state(state) do
    fixture = state[:fixture]
    portfolio = state[:portfolio_runtime] || %{}

    %{
      repos: model_repos(fixture, portfolio),
      workspaces: model_workspaces(portfolio),
      snapshots: model_list(portfolio[:snapshots], :snapshot_id),
      artifacts: model_list(portfolio[:artifacts], :artifact_id),
      graph: graph_model(portfolio),
      search_terms: search_terms(fixture)
    }
  end

  def report(model) do
    %{
      "repos" => map_size(model.repos),
      "workspaces" => map_size(model.workspaces),
      "snapshots" => map_size(model.snapshots),
      "artifacts" => map_size(model.artifacts),
      "graphRepos" => map_size(model.graph),
      "searchTerms" => map_size(model.search_terms)
    }
  end

  defp model_repos(nil, _portfolio), do: %{}

  defp model_repos(fixture, portfolio) do
    runtime_repos =
      portfolio
      |> Map.get(:repos, [])
      |> Enum.map(&{&1.repo_id || &1.name, &1})
      |> Map.new()

    fixture.local_repos
    |> Enum.map(fn repo ->
      id = repo[:repo_id] || repo.name
      runtime = runtime_repos[id] || %{}

      {id,
       %{
         name: repo.name,
         default_ref: repo[:default_ref] || "refs/heads/main",
         refs: MapSet.new(repo[:branches] || ["refs/heads/main"]),
         files_by_ref: %{"refs/heads/main" => files(repo)},
         deleted?: Map.get(runtime, :deleted?, false)
       }}
    end)
    |> Map.new()
  end

  defp files(repo) do
    (repo[:files] || [])
    |> Enum.map(&{&1.path, %{path: &1.path, sha256: &1[:sha256], byte_length: &1[:byte_length]}})
    |> Map.new()
  end

  defp model_workspaces(portfolio) do
    portfolio
    |> Map.get(:active_workspaces, [])
    |> Enum.map(fn workspace ->
      {workspace.workspace_id,
       %{
         repo_id: workspace.repo_id,
         open?: Map.get(workspace, :open?, true),
         pending_changes: Map.get(workspace, :pending_changes, 0),
         files: Map.get(workspace, :written_files, %{}),
         deleted_paths: Map.get(workspace, :deleted_paths, MapSet.new())
       }}
    end)
    |> Map.new()
  end

  defp model_list(nil, _key), do: %{}

  defp model_list(values, key) do
    values
    |> List.wrap()
    |> Enum.map(&{Map.get(&1, key), &1})
    |> Enum.reject(fn {id, _} -> is_nil(id) end)
    |> Map.new()
  end

  defp graph_model(portfolio) do
    portfolio
    |> Map.get(:graph_ready_repos, MapSet.new())
    |> Enum.map(&{&1, %{ready?: true}})
    |> Map.new()
  end

  defp search_terms(nil), do: %{}

  defp search_terms(fixture) do
    get_in(fixture, [:expected, :search_hits]) || %{}
  end
end
