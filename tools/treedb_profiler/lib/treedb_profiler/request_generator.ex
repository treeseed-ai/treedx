defmodule TreeDbProfiler.RequestGenerator do
  @moduledoc false

  alias TreeDbProfiler.{DataGenerator, GitFixture, PortfolioState, ProfileRequest}

  @read_ops [
    :read_repository_file,
    :search_repository_files,
    :query_repository,
    :workspace_status
  ]
  @write_ops [:create_workspace, :write_workspace_file, :patch_workspace_file]
  @graph_ops [:refresh_graph, :query_graph, :build_context]
  @artifact_ops [:build_snapshot, :export_artifact]

  def next(portfolio_pid, opts) do
    operation =
      portfolio_pid
      |> candidates(opts)
      |> weighted_pick()

    build(operation, portfolio_pid, opts)
  end

  def candidates(portfolio_pid, opts) do
    snapshot = PortfolioState.snapshot(portfolio_pid)
    workspace? = snapshot.active_workspaces != []

    can_create_workspace? =
      snapshot.repos != [] and length(snapshot.active_workspaces) < max_active_workspaces(opts)

    artifact? = snapshot.artifacts != []
    create_repo? = PortfolioState.can_create_repo?(portfolio_pid)

    base =
      []
      |> maybe_add(:create_repository, opts.portfolio_create_weight, create_repo?)
      |> maybe_add(:create_workspace, weight(opts, 1), can_create_workspace?)
      |> maybe_add(:write_workspace_file, weight(opts, 12), workspace?)
      |> maybe_add(:patch_workspace_file, weight(opts, 8), workspace?)
      |> maybe_add(
        :delete_workspace_file,
        weight(opts, 2),
        workspace? and opts.include_destructive
      )
      |> maybe_add(:read_repository_file, weight(opts, 20), snapshot.repos != [])
      |> maybe_add(:search_repository_files, weight(opts, 12), snapshot.repos != [])
      |> maybe_add(:query_repository, weight(opts, 8), snapshot.repos != [])
      |> maybe_add(:refresh_graph, weight(opts, 4), snapshot.repos != [])
      |> maybe_add(:query_graph, weight(opts, 6), snapshot.repos != [])
      |> maybe_add(:build_context, weight(opts, 6), snapshot.repos != [])
      |> maybe_add(:build_snapshot, weight(opts, 2), snapshot.repos != [])
      |> maybe_add(:export_artifact, weight(opts, 1), snapshot.snapshots != [])
      |> maybe_add(:get_artifact, 1, artifact?)

    maybe_add(
      base,
      :delete_repository,
      opts.portfolio_delete_weight,
      deletion_supported?() and opts.include_destructive
    )
  end

  defp max_active_workspaces(%{portfolio_growth_target: "sparse"}), do: 16
  defp max_active_workspaces(%{portfolio_growth_target: "aggressive"}), do: 64
  defp max_active_workspaces(_opts), do: 32

  def build(:create_repository, portfolio_pid, opts) do
    index = PortfolioState.next_counter(portfolio_pid, :repo)
    repo_def = PortfolioState.portfolio_fixture(opts, index)
    root = Path.join([opts.fixture_root, opts.profile_id, "portfolio"])
    File.mkdir_p!(root)
    repo = GitFixture.create_repo!(root, repo_def, "#{opts.profile_id}:portfolio:#{index}")

    request(
      "registerRepository",
      :create,
      :post,
      "/api/v1/repos/register",
      "repository",
      %{
        "name" => repo.name,
        "localPath" => repo.path
      },
      seed: opts.profile_id,
      effect: %{kind: :repo_registered, repo: repo}
    )
  end

  def build(:create_workspace, portfolio_pid, opts) do
    case PortfolioState.reserve_workspace_repo(portfolio_pid) do
      nil ->
        build(:read_repository_file, portfolio_pid, opts)

      repo ->
        request(
          "createWorkspace",
          :create,
          :post,
          "/api/v1/repos/#{repo.repo_id}/workspaces",
          "workspace",
          %{
            "baseRef" => repo.default_ref,
            "branchName" =>
              "refs/heads/profiler/#{opts.profile_id}/#{System.unique_integer([:positive])}",
            "mode" => "writable",
            "allowedPaths" => ["docs/**", "plain/**", "data/**", "assets/**", "workspace/**"]
          },
          seed: opts.profile_id,
          effect: %{kind: :workspace_created, repo_id: repo.repo_id},
          failure_effect: %{kind: :workspace_create_finished, repo_id: repo.repo_id}
        )
    end
  end

  def build(:write_workspace_file, portfolio_pid, opts) do
    with_workspace(portfolio_pid, opts, fn workspace ->
      counter = PortfolioState.next_counter(portfolio_pid, :file)
      path = DataGenerator.generated_path(:markdown, counter)
      content = DataGenerator.markdown(opts.profile_id, counter)

      request(
        "writeWorkspaceFile",
        :write,
        :put,
        "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
        "workspace",
        %{"content" => content},
        expected: [200, 404, 409],
        seed: opts.profile_id,
        effect: %{
          kind: :file_written,
          workspace_id: workspace.workspace_id,
          path: path,
          content: content
        }
      )
    end)
  end

  def build(:patch_workspace_file, portfolio_pid, opts) do
    with_workspace(portfolio_pid, opts, fn workspace ->
      counter = PortfolioState.next_counter(portfolio_pid, :file)
      path = DataGenerator.generated_path(:markdown, counter)

      content =
        DataGenerator.markdown(opts.profile_id, counter) <> "\npatched release #{counter}\n"

      request(
        "patchWorkspaceFile",
        :update,
        :patch,
        "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
        "workspace",
        %{"content" => content},
        expected: [200, 404, 409],
        seed: opts.profile_id,
        effect: %{
          kind: :file_written,
          workspace_id: workspace.workspace_id,
          path: path,
          content: content
        }
      )
    end)
  end

  def build(:delete_workspace_file, portfolio_pid, opts) do
    with_workspace(portfolio_pid, opts, fn workspace ->
      counter = PortfolioState.next_counter(portfolio_pid, :file)
      path = DataGenerator.generated_path(:delete, counter)

      request(
        "deleteWorkspaceFile",
        :delete,
        :delete,
        "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
        "workspace",
        nil,
        expected: [200, 404, 409],
        seed: opts.profile_id,
        effect: %{kind: :file_deleted, workspace_id: workspace.workspace_id, path: path}
      )
    end)
  end

  def build(:commit_workspace, portfolio_pid, opts) do
    with_reserved_dirty_workspace(portfolio_pid, opts, fn workspace ->
      request(
        "commitWorkspace",
        :update,
        :post,
        "/api/v1/workspaces/#{workspace.workspace_id}/commit",
        "workspace",
        %{
          "message" => "Profiler portfolio commit",
          "author" => %{"name" => "TreeDB Profiler", "email" => "profiler@example.invalid"}
        },
        expected: [200, 404, 409, 422],
        seed: opts.profile_id,
        effect: %{kind: :workspace_committed, workspace_id: workspace.workspace_id},
        failure_effect: %{kind: :workspace_commit_finished, workspace_id: workspace.workspace_id}
      )
    end)
  end

  def build(:close_workspace, portfolio_pid, opts) do
    with_workspace(portfolio_pid, opts, fn workspace ->
      request(
        "closeWorkspace",
        :delete,
        :post,
        "/api/v1/workspaces/#{workspace.workspace_id}/close",
        "workspace",
        %{"reason" => "portfolio lifecycle"},
        expected: [200, 404, 409],
        seed: opts.profile_id,
        effect: %{kind: :workspace_closed, workspace_id: workspace.workspace_id}
      )
    end)
  end

  def build(:read_repository_file, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)

    path =
      PortfolioState.choose_readable_path(portfolio_pid, repo.repo_id) ||
        %{
          path: "docs/topic-01/doc-000001.md"
        }

    request(
      "readRepositoryFile",
      :read,
      :post,
      "/api/v1/repos/#{repo.repo_id}/files/read",
      "repository_read",
      %{"ref" => repo.default_ref, "path" => path.path, "parseFrontmatter" => true},
      seed: opts.profile_id
    )
  end

  def build(:search_repository_files, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)

    request(
      "searchRepositoryFiles",
      :query,
      :post,
      "/api/v1/repos/#{repo.repo_id}/files/search",
      "repository_read",
      %{"paths" => ["docs/**", "workspace/**"], "query" => "release", "limit" => 20},
      seed: opts.profile_id
    )
  end

  def build(:query_repository, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)

    request(
      "queryRepository",
      :query,
      :post,
      "/api/v1/repos/#{repo.repo_id}/query",
      "repository_query",
      %{
        "ref" => repo.default_ref,
        "type" => "combined",
        "query" => "release",
        "paths" => ["docs/**", "workspace/**"],
        "limit" => 20
      },
      seed: opts.profile_id
    )
  end

  def build(:workspace_status, portfolio_pid, opts) do
    with_workspace(portfolio_pid, opts, fn workspace ->
      request(
        "getWorkspaceStatus",
        :read,
        :get,
        "/api/v1/workspaces/#{workspace.workspace_id}/status",
        "workspace",
        nil,
        expected: [200, 404, 409],
        seed: opts.profile_id
      )
    end)
  end

  def build(:refresh_graph, portfolio_pid, opts) do
    case PortfolioState.reserve_graph_refresh_repo(portfolio_pid) do
      nil ->
        build(:read_repository_file, portfolio_pid, opts)

      repo ->
        request(
          "refreshRepositoryGraph",
          :graph,
          :post,
          "/api/v1/repos/#{repo.repo_id}/graph/refresh",
          "graph",
          %{
            "ref" => repo.default_ref,
            "paths" => ["docs/**", "workspace/**"],
            "incremental" => true
          },
          seed: opts.profile_id,
          effect: %{kind: :graph_refreshed, repo_id: repo.repo_id},
          failure_effect: %{kind: :graph_refresh_finished, repo_id: repo.repo_id}
        )
    end
  end

  def build(:query_graph, portfolio_pid, opts) do
    case PortfolioState.choose_graph_repo(portfolio_pid) do
      nil ->
        build(:refresh_graph, portfolio_pid, opts)

      repo ->
        request(
          "queryRepositoryGraph",
          :graph,
          :post,
          "/api/v1/repos/#{repo.repo_id}/graph/query",
          "graph",
          %{"ref" => repo.default_ref, "query" => "release", "options" => %{"limit" => 20}},
          expected: [200, 404],
          seed: opts.profile_id
        )
    end
  end

  def build(:build_context, portfolio_pid, opts) do
    case PortfolioState.choose_graph_repo(portfolio_pid) do
      nil ->
        build(:refresh_graph, portfolio_pid, opts)

      repo ->
        request(
          "buildContext",
          :query,
          :post,
          "/api/v1/repos/#{repo.repo_id}/context/build",
          "context",
          %{
            "ref" => repo.default_ref,
            "query" => "release",
            "budget" => %{"maxNodes" => 10, "maxTokens" => 2000}
          },
          expected: [200, 404],
          seed: opts.profile_id
        )
    end
  end

  def build(:build_snapshot, portfolio_pid, opts) do
    case PortfolioState.reserve_snapshot_repo(portfolio_pid) do
      nil ->
        build(:read_repository_file, portfolio_pid, opts)

      repo ->
        request(
          "buildSnapshot",
          :artifact,
          :post,
          "/api/v1/repos/#{repo.repo_id}/snapshots/build",
          "snapshot",
          %{
            "ref" => repo.default_ref,
            "kind" => "repository_snapshot",
            "paths" => ["docs/**", "workspace/**"],
            "includeGraph" => false
          },
          seed: opts.profile_id,
          effect: %{kind: :snapshot_built, repo_id: repo.repo_id},
          failure_effect: %{kind: :snapshot_finished, repo_id: repo.repo_id}
        )
    end
  end

  def build(:export_artifact, portfolio_pid, opts) do
    snapshot = PortfolioState.snapshot(portfolio_pid).snapshots |> List.first()
    repo = PortfolioState.choose_repo(portfolio_pid)

    if is_nil(snapshot) do
      build(:build_snapshot, portfolio_pid, opts)
    else
      request(
        "exportArtifact",
        :artifact,
        :post,
        "/api/v1/repos/#{snapshot.repo_id || repo.repo_id}/artifacts/export",
        "artifact",
        %{"snapshotId" => snapshot.snapshot_id},
        seed: opts.profile_id,
        effect: %{kind: :artifact_exported, repo_id: snapshot.repo_id || repo.repo_id}
      )
    end
  end

  def build(:get_artifact, portfolio_pid, opts) do
    artifact = PortfolioState.choose_artifact(portfolio_pid)

    if is_nil(artifact) do
      build(:build_snapshot, portfolio_pid, opts)
    else
      request(
        "getArtifact",
        :read,
        :get,
        "/api/v1/repos/#{artifact.repo_id}/artifacts/#{artifact.artifact_id}",
        "artifact",
        nil,
        expected: [200, 404],
        seed: opts.profile_id
      )
    end
  end

  def build(:delete_repository, _portfolio_pid, opts) do
    request(
      "deleteRepository",
      :delete,
      :delete,
      "/api/v1/repos/not-supported",
      "repository",
      nil,
      expected: [404, 405],
      seed: opts.profile_id,
      effect: nil
    )
  end

  def operation_groups do
    %{
      read: @read_ops,
      write: @write_ops,
      graph: @graph_ops,
      artifact: @artifact_ops
    }
  end

  defp request(operation_id, type, method, path, category, body, opts) do
    ProfileRequest.new(%{
      id: "req_#{System.unique_integer([:positive])}",
      operation_id: operation_id,
      operation_type: type,
      method: method,
      path_template: template(path),
      path: path,
      category: category,
      body: body,
      headers: Keyword.get(opts, :headers, []),
      expected_status: List.wrap(Keyword.get(opts, :expected, 200)),
      validation_rule: validation_rule(operation_id),
      state_effect: Keyword.get(opts, :effect),
      failure_effect: Keyword.get(opts, :failure_effect),
      seed: Keyword.fetch!(opts, :seed)
    })
  end

  defp maybe_add(values, _operation, _weight, false), do: values
  defp maybe_add(values, _operation, weight, true) when weight <= 0, do: values
  defp maybe_add(values, operation, weight, true), do: [{operation, weight} | values]

  defp weighted_pick([]), do: :read_repository_file

  defp weighted_pick(weighted) do
    total = Enum.sum(Enum.map(weighted, &elem(&1, 1)))
    pick = :rand.uniform(max(total, 1))

    weighted
    |> Enum.reduce_while(0, fn {operation, weight}, acc ->
      next = acc + weight
      if pick <= next, do: {:halt, operation}, else: {:cont, next}
    end)
  end

  defp weight(%{portfolio_growth_target: "sparse"}, base), do: max(div(base, 2), 1)
  defp weight(%{portfolio_growth_target: "aggressive"}, base), do: base * 2
  defp weight(_opts, base), do: base

  defp deletion_supported?, do: false

  defp with_workspace(portfolio_pid, opts, fun) do
    case PortfolioState.choose_workspace(portfolio_pid) do
      nil -> build(:create_workspace, portfolio_pid, opts)
      workspace -> fun.(workspace)
    end
  end

  defp with_reserved_dirty_workspace(portfolio_pid, opts, fun) do
    case PortfolioState.reserve_dirty_workspace(portfolio_pid) do
      nil -> build(:write_workspace_file, portfolio_pid, opts)
      workspace -> fun.(workspace)
    end
  end

  defp validation_rule(operation_id) do
    get_in(TreeDbProfiler.EndpointMatrix.operation_map(), [operation_id, "validation", "rule"]) ||
      "ok_envelope"
  end

  defp template(path) do
    path
    |> String.replace(~r/repo_[A-Za-z0-9_-]+/, "{repo_id}")
    |> String.replace(~r/ws_[A-Za-z0-9_-]+/, "{workspace_id}")
    |> String.replace(~r/snap_[A-Za-z0-9_-]+/, "{snapshot_id}")
    |> String.replace(~r/artifact_[A-Za-z0-9_-]+/, "{artifact_id}")
    |> String.replace(~r/\?.*$/, "")
  end
end
