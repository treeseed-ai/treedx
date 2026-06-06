defmodule TreeDxProfiler.RequestGenerator do
  @moduledoc false

  alias TreeDxProfiler.{
    DataGenerator,
    GitFixture,
    Hash,
    PortfolioState,
    ProfileRequest,
    SemanticExpectation
  }

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
    active_workspace_count = length(snapshot.active_workspaces)

    target_workspace_count =
      min(max_active_workspaces(opts), max(Map.get(opts, :concurrency, 1), 1))

    ramping_workspaces? = active_workspace_count < target_workspace_count

    can_create_workspace? =
      snapshot.repos != [] and length(snapshot.active_workspaces) < max_active_workspaces(opts)

    artifact? = snapshot.artifacts != []
    create_repo? = PortfolioState.can_create_repo?(portfolio_pid)

    base =
      []
      |> maybe_add(
        :create_repository,
        weight(opts, :create_repository, opts.portfolio_create_weight),
        create_repo?
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
      |> maybe_add(:get_artifact, weight(opts, :get_artifact, 1), artifact?)

    maybe_add(
      base,
      :delete_repository,
      weight(opts, :delete_repository, opts.portfolio_delete_weight),
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
      "importLocalRepository",
      :create,
      :post,
      "/api/v1/admin/repos/import-local",
      "repository",
      %{
        "repositoryName" => repo.name,
        "sourceRelativePath" => source_relative_path(repo.path, opts)
      },
      seed: opts.profile_id,
      target: %{repo_name: repo.name},
      expectation: %{repo_name: repo.name},
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
          target: %{repo_id: repo.repo_id},
          expectation: %{repo_id: repo.repo_id, default_ref: repo.default_ref},
          effect_on_status: %{200 => %{kind: :workspace_created, repo_id: repo.repo_id}},
          effect: %{kind: :workspace_created, repo_id: repo.repo_id},
          failure_effect: %{kind: :workspace_create_finished, repo_id: repo.repo_id}
        )
    end
  end

  def build(:write_workspace_file, portfolio_pid, opts) do
    with_reserved_workspace(portfolio_pid, opts, fn workspace ->
      counter = PortfolioState.next_counter(portfolio_pid, :file)
      path = DataGenerator.generated_path(:markdown, counter)
      content = DataGenerator.markdown(opts.profile_id, counter)

      effect = %{
        kind: :file_written,
        workspace_id: workspace.workspace_id,
        path: path,
        content: content
      }

      request(
        "writeWorkspaceFile",
        :write,
        :put,
        "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
        "workspace",
        %{"content" => content},
        expected: [200, 404, 409],
        seed: opts.profile_id,
        target: %{workspace_id: workspace.workspace_id, repo_id: workspace.repo_id, path: path},
        expectation: semantic_content(content, path),
        probes: [
          %{kind: :workspace_file_content_equals},
          %{kind: :workspace_status_mentions_path},
          %{kind: :workspace_diff_mentions_path}
        ],
        race: %{acceptable_statuses: [404, 409]},
        effect_on_status: %{200 => effect},
        effect: effect,
        failure_effect: %{
          kind: :workspace_mutation_finished,
          workspace_id: workspace.workspace_id
        }
      )
    end)
  end

  def build(:patch_workspace_file, portfolio_pid, opts) do
    case PortfolioState.reserve_workspace_file(portfolio_pid) do
      nil ->
        build(:write_workspace_file, portfolio_pid, opts)

      {workspace, file} ->
        counter = PortfolioState.next_counter(portfolio_pid, :file)
        path = file.path
        content = patch_content(file.content, counter)
        patch = replace_first_line_patch(path, file.content, content)

        effect = %{
          kind: :file_written,
          workspace_id: workspace.workspace_id,
          path: path,
          content: content
        }

        request(
          "patchWorkspaceFile",
          :update,
          :patch,
          "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
          "workspace",
          %{"patch" => patch},
          expected: [200, 404, 409],
          seed: opts.profile_id,
          target: %{workspace_id: workspace.workspace_id, repo_id: workspace.repo_id, path: path},
          expectation: semantic_content(content, path),
          probes: [
            %{kind: :workspace_file_content_equals},
            %{kind: :workspace_status_mentions_path},
            %{kind: :workspace_diff_mentions_path}
          ],
          race: %{acceptable_statuses: [404, 409]},
          effect_on_status: %{200 => effect},
          effect: effect,
          failure_effect: %{
            kind: :workspace_mutation_finished,
            workspace_id: workspace.workspace_id
          }
        )
    end
  end

  def build(:delete_workspace_file, portfolio_pid, opts) do
    case PortfolioState.reserve_workspace_file(portfolio_pid) do
      nil ->
        build(:write_workspace_file, portfolio_pid, opts)

      {workspace, file} ->
        path = file.path
        effect = %{kind: :file_deleted, workspace_id: workspace.workspace_id, path: path}

        request(
          "deleteWorkspaceFile",
          :delete,
          :delete,
          "/api/v1/workspaces/#{workspace.workspace_id}/files?path=#{URI.encode_www_form(path)}",
          "workspace",
          nil,
          expected: [200, 404, 409],
          seed: opts.profile_id,
          target: %{workspace_id: workspace.workspace_id, repo_id: workspace.repo_id, path: path},
          probes: [%{kind: :workspace_file_absent}],
          race: %{acceptable_statuses: [404, 409]},
          effect_on_status: %{200 => effect},
          effect: effect,
          failure_effect: %{
            kind: :workspace_mutation_finished,
            workspace_id: workspace.workspace_id
          }
        )
    end
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
          "author" => %{"name" => "TreeDX Profiler", "email" => "profiler@example.invalid"}
        },
        expected: [200, 404, 409, 422],
        seed: opts.profile_id,
        target: %{workspace_id: workspace.workspace_id, repo_id: workspace.repo_id},
        race: %{acceptable_statuses: [404, 409, 422]},
        effect_on_status: %{
          200 => %{kind: :workspace_committed, workspace_id: workspace.workspace_id}
        },
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
        target: %{workspace_id: workspace.workspace_id, repo_id: workspace.repo_id},
        race: %{acceptable_statuses: [404, 409]},
        effect_on_status: %{
          200 => %{kind: :workspace_closed, workspace_id: workspace.workspace_id}
        },
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
      seed: opts.profile_id,
      target: %{repo_id: repo.repo_id, path: path.path, ref: repo.default_ref},
      expectation: Map.take(path, [:path, :content, :sha256, :byte_length])
    )
  end

  def build(:list_repository_paths, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)

    expected =
      repo.readable_paths
      |> List.first()
      |> case do
        nil -> %{}
        file -> %{expected_path: file.path}
      end

    request(
      "listRepositoryPaths",
      :read,
      :post,
      "/api/v1/repos/#{repo.repo_id}/paths/list",
      "repository_read",
      %{"ref" => repo.default_ref, "paths" => ["docs/**", "workspace/**"], "limit" => 50},
      seed: opts.profile_id,
      target: %{repo_id: repo.repo_id},
      expectation: expected
    )
  end

  def build(:search_repository_files, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)
    expected = expected_search(repo)
    term = expected[:term] || "release"

    request(
      "searchRepositoryFiles",
      :query,
      :post,
      "/api/v1/repos/#{repo.repo_id}/files/search",
      "repository_read",
      %{"paths" => ["docs/**", "workspace/**"], "query" => term, "limit" => 20},
      seed: opts.profile_id,
      target: %{repo_id: repo.repo_id, ref: repo.default_ref},
      expectation: expected
    )
  end

  def build(:query_repository, portfolio_pid, opts) do
    repo = PortfolioState.choose_repo(portfolio_pid)
    expected = expected_search(repo)
    term = expected[:term] || "release"

    request(
      "queryRepository",
      :query,
      :post,
      "/api/v1/repos/#{repo.repo_id}/query",
      "repository_query",
      %{
        "ref" => repo.default_ref,
        "type" => "combined",
        "query" => term,
        "paths" => ["docs/**", "workspace/**"],
        "limit" => 20
      },
      seed: opts.profile_id,
      target: %{repo_id: repo.repo_id, ref: repo.default_ref},
      expectation: expected
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
          target: %{repo_id: repo.repo_id, ref: repo.default_ref},
          race: %{acceptable_statuses: [404, 409]},
          effect_on_status: %{200 => %{kind: :graph_refreshed, repo_id: repo.repo_id}},
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
          seed: opts.profile_id,
          target: %{repo_id: repo.repo_id, ref: repo.default_ref},
          race: %{acceptable_statuses: [404]}
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
          seed: opts.profile_id,
          target: %{repo_id: repo.repo_id, ref: repo.default_ref},
          race: %{acceptable_statuses: [404]}
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
          target: %{repo_id: repo.repo_id, ref: repo.default_ref},
          race: %{acceptable_statuses: [409]},
          effect_on_status: %{200 => %{kind: :snapshot_built, repo_id: repo.repo_id}},
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
        target: %{repo_id: snapshot.repo_id || repo.repo_id, snapshot_id: snapshot.snapshot_id},
        expectation: %{snapshot_id: snapshot.snapshot_id},
        race: %{acceptable_statuses: [404, 409]},
        effect_on_status: %{
          200 => %{kind: :artifact_exported, repo_id: snapshot.repo_id || repo.repo_id}
        },
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
        seed: opts.profile_id,
        target: %{repo_id: artifact.repo_id, artifact_id: artifact.artifact_id},
        expectation: %{artifact_id: artifact.artifact_id},
        race: %{acceptable_statuses: [404]}
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
    effect = Keyword.get(opts, :effect)

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
      target: Keyword.get(opts, :target, %{}),
      expectation: Keyword.get(opts, :expectation, %{}),
      postconditions: Keyword.get(opts, :postconditions, []),
      race_context: Keyword.get(opts, :race, %{}),
      validation_probes: Keyword.get(opts, :probes, []),
      state_effect_on_status:
        Keyword.get(opts, :effect_on_status, if(effect, do: %{200 => effect}, else: %{})),
      state_effect: effect,
      failure_effect: Keyword.get(opts, :failure_effect),
      seed: Keyword.fetch!(opts, :seed)
    })
  end

  defp semantic_content(content, path) do
    content
    |> SemanticExpectation.content_expectation(%{path: path, byte_length: byte_size(content)})
    |> Map.put(:sha256, Hash.sha256(content))
  end

  defp patch_content(content, counter) do
    case String.split(content || "", "\n", parts: 2) do
      [first, rest] -> first <> " patched-#{counter}\n" <> rest
      [first] -> first <> " patched-#{counter}"
      [] -> "patched-#{counter}"
    end
  end

  defp replace_first_line_patch(path, old_content, new_content) do
    old_first = old_content |> to_string() |> String.split("\n", parts: 2) |> List.first()
    new_first = new_content |> to_string() |> String.split("\n", parts: 2) |> List.first()

    [
      "--- a/#{path}",
      "+++ b/#{path}",
      "@@ -1,1 +1,1 @@",
      "-#{old_first}",
      "+#{new_first}"
    ]
    |> Enum.join("\n")
  end

  defp expected_search(repo) do
    file =
      repo.readable_paths
      |> Enum.find(&is_binary(Map.get(&1, :content)))

    if file do
      %{
        term: file.content |> SemanticExpectation.preferred_term(),
        expected_path: file.path,
        content: file.content,
        sha256: file.sha256
      }
    else
      %{term: "release"}
    end
  end

  defp source_relative_path(path, opts) do
    data_dir = System.get_env("TREEDX_DATA_DIR") || Map.get(opts, :data_dir) || "/var/lib/treedx"

    path
    |> Path.expand()
    |> Path.relative_to(Path.expand(data_dir))
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

  defp weight(%{profile_purpose: "performance"} = opts, operation, base) do
    opts
    |> performance_mix()
    |> Map.get(operation, base)
    |> round_weight()
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

  defp with_workspace(portfolio_pid, opts, fun) do
    case PortfolioState.choose_workspace(portfolio_pid) do
      nil -> build(:create_workspace, portfolio_pid, opts)
      workspace -> fun.(workspace)
    end
  end

  defp with_reserved_workspace(portfolio_pid, opts, fun) do
    case PortfolioState.reserve_workspace(portfolio_pid) do
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
    get_in(TreeDxProfiler.EndpointMatrix.operation_map(), [operation_id, "validation", "rule"]) ||
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
