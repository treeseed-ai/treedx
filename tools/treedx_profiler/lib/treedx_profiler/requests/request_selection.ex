defmodule TreeDxProfiler.RequestSelection do
  @moduledoc false

  alias TreeDxProfiler.PortfolioState

  @read_ops [
    :read_repository_file,
    :list_repository_paths,
    :search_repository_files,
    :query_repository,
    :workspace_status
  ]
  @write_ops [:create_workspace, :write_workspace_file, :patch_workspace_file]
  @graph_ops [:refresh_graph, :query_graph, :build_context]
  @artifact_ops [:build_snapshot, :export_artifact]

  def pick(portfolio_pid, opts) do
    portfolio_pid
    |> candidates(opts)
    |> weighted_pick()
  end

  def candidates(portfolio_pid, opts) do
    snapshot = PortfolioState.snapshot(portfolio_pid)
    workspace? = snapshot.active_workspaces != []
    active_workspace_count = length(snapshot.active_workspaces)

    target_workspace_count =
      min(max_active_workspaces(opts), max(Map.get(opts, :concurrency, 1), 1))

    ramping_workspaces? = active_workspace_count < target_workspace_count

    can_create_workspace? =
      snapshot.repos != [] and length(snapshot.active_workspaces) < max_active_workspaces(opts)

    base =
      []
      |> maybe_add(
        :create_repository,
        weight(opts, :create_repository, opts.portfolio_create_weight),
        PortfolioState.can_create_repo?(portfolio_pid)
      )
      |> maybe_add(
        :create_workspace,
        if(ramping_workspaces?, do: 24, else: weight(opts, :create_workspace, 1)),
        can_create_workspace?
      )
      |> maybe_add(
        :write_workspace_file,
        weight(opts, :write_workspace_file, 12),
        workspace? and not ramping_workspaces?
      )
      |> maybe_add(
        :patch_workspace_file,
        weight(opts, :patch_workspace_file, 8),
        workspace? and not ramping_workspaces?
      )
      |> maybe_add(
        :delete_workspace_file,
        weight(opts, :delete_workspace_file, 2),
        workspace? and opts.include_destructive and not ramping_workspaces?
      )
      |> maybe_add(
        :read_repository_file,
        weight(opts, :read_repository_file, 20),
        snapshot.repos != []
      )
      |> maybe_add(
        :list_repository_paths,
        weight(opts, :list_repository_paths, 8),
        snapshot.repos != []
      )
      |> maybe_add(
        :search_repository_files,
        weight(opts, :search_repository_files, 12),
        snapshot.repos != []
      )
      |> maybe_add(:query_repository, weight(opts, :query_repository, 8), snapshot.repos != [])
      |> maybe_add(:refresh_graph, weight(opts, :refresh_graph, 4), snapshot.repos != [])
      |> maybe_add(:query_graph, weight(opts, :query_graph, 6), snapshot.repos != [])
      |> maybe_add(:build_context, weight(opts, :build_context, 6), snapshot.repos != [])
      |> maybe_add(:build_snapshot, weight(opts, :build_snapshot, 2), snapshot.repos != [])
      |> maybe_add(:export_artifact, weight(opts, :export_artifact, 1), snapshot.snapshots != [])
      |> maybe_add(:get_artifact, weight(opts, :get_artifact, 1), snapshot.artifacts != [])

    maybe_add(
      base,
      :delete_repository,
      weight(opts, :delete_repository, opts.portfolio_delete_weight),
      deletion_supported?() and opts.include_destructive
    )
  end

  def operation_groups,
    do: %{read: @read_ops, write: @write_ops, graph: @graph_ops, artifact: @artifact_ops}

  defp max_active_workspaces(%{portfolio_growth_target: "sparse"}), do: 16
  defp max_active_workspaces(%{portfolio_growth_target: "aggressive"}), do: 64
  defp max_active_workspaces(_opts), do: 32

  defp maybe_add(values, _operation, _weight, false), do: values
  defp maybe_add(values, _operation, weight, true) when weight <= 0, do: values
  defp maybe_add(values, operation, weight, true), do: [{operation, weight} | values]

  defp weighted_pick([]), do: :read_repository_file

  defp weighted_pick(weighted) do
    total = Enum.sum(Enum.map(weighted, &elem(&1, 1)))
    pick = :rand.uniform(max(total, 1))

    Enum.reduce_while(weighted, 0, fn {operation, weight}, acc ->
      next = acc + weight
      if pick <= next, do: {:halt, operation}, else: {:cont, next}
    end)
  end

  defp weight(%{profile_purpose: "performance"} = opts, operation, base) do
    opts |> performance_mix() |> Map.get(operation, base) |> round_weight()
  end

  defp weight(%{portfolio_growth_target: "sparse"}, _operation, base), do: max(div(base, 2), 1)
  defp weight(%{portfolio_growth_target: "aggressive"}, _operation, base), do: base * 2
  defp weight(_opts, _operation, base), do: base

  defp performance_mix(%{performance_workload: "read_mostly"}) do
    %{
      read_repository_file: 30,
      search_repository_files: 20,
      query_repository: 15,
      list_repository_paths: 15,
      query_graph: 8,
      build_context: 5,
      write_workspace_file: 4,
      patch_workspace_file: 2,
      build_snapshot: 1,
      create_repository: 0.2,
      refresh_graph: 1,
      export_artifact: 0.2,
      get_artifact: 1
    }
  end

  defp performance_mix(%{performance_workload: "write_mixed"}) do
    %{
      write_workspace_file: 18,
      patch_workspace_file: 14,
      delete_workspace_file: 5,
      workspace_status: 10,
      read_repository_file: 12,
      search_repository_files: 8,
      query_repository: 8,
      build_snapshot: 2,
      refresh_graph: 2,
      create_repository: 1
    }
  end

  defp performance_mix(_opts) do
    %{
      read_repository_file: 20,
      search_repository_files: 14,
      query_repository: 12,
      list_repository_paths: 10,
      write_workspace_file: 10,
      patch_workspace_file: 8,
      delete_workspace_file: 3,
      workspace_status: 6,
      query_graph: 5,
      build_context: 4,
      refresh_graph: 2,
      build_snapshot: 1,
      export_artifact: 0.5,
      create_repository: 0.5
    }
  end

  defp round_weight(value) when is_float(value), do: trunc(value * 10)
  defp round_weight(value), do: value
  defp deletion_supported?, do: false
end
