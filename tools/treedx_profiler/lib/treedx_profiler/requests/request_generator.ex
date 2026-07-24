defmodule TreeDxProfiler.RequestGenerator do
  @moduledoc false

  alias TreeDxProfiler.{DataGenerator, GitFixture, PortfolioState, RequestFactory}

  def next(portfolio_pid, opts) do
    build(TreeDxProfiler.RequestSelection.pick(portfolio_pid, opts), portfolio_pid, opts)
  end

  def candidates(portfolio_pid, opts),
    do: TreeDxProfiler.RequestSelection.candidates(portfolio_pid, opts)

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
        "sourceRelativePath" => RequestFactory.source_relative_path(repo.path, opts)
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
        expectation: RequestFactory.semantic_content(content, path),
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
        content = RequestFactory.patch_content(file.content, counter)
        patch = RequestFactory.replace_first_line_patch(path, file.content, content)

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
          expectation: RequestFactory.semantic_content(content, path),
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
    expected = RequestFactory.expected_search(repo)
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
    expected = RequestFactory.expected_search(repo)
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
    with_workspace(portfolio_pid, opts, &RequestFactory.workspace_status(&1, opts))
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

  def build(:delete_repository, _portfolio_pid, opts), do: RequestFactory.unsupported_delete(opts)

  def operation_groups, do: TreeDxProfiler.RequestSelection.operation_groups()

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

  defp request(operation_id, type, method, path, category, body, opts),
    do: RequestFactory.request(operation_id, type, method, path, category, body, opts)
end
