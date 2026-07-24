defmodule TreeDxProfiler.RequestGeneratorTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{Fixtures, PortfolioState, RequestGenerator}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "treedx-profiler-generator-#{System.unique_integer([:positive])}"
      )

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "generator-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "generator-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "generator-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_create_weight: 3,
      portfolio_delete_weight: 1,
      portfolio_growth_target: "steady",
      portfolio_repo_prefix: "profile-",
      include_destructive: false
    }

    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, pid} = PortfolioState.start_link(opts)
    %{pid: pid, opts: opts}
  end

  test "create repository request uses configured prefix", %{pid: pid, opts: opts} do
    request = RequestGenerator.build(:create_repository, pid, opts)

    assert request.operation_id == "importLocalRepository"
    assert request.operation_type == :create
    assert request.body["repositoryName"] =~ "profile-generator-test-repo-"
    assert request.state_effect.kind == :repo_registered
  end

  test "generator does not choose workspace writes before workspace setup", %{
    pid: pid,
    opts: opts
  } do
    candidates = RequestGenerator.candidates(pid, opts) |> Enum.map(&elem(&1, 0))

    refute :write_workspace_file in candidates
    assert :create_workspace in candidates
    assert :read_repository_file in candidates
  end

  test "workspace write request is generated after workspace setup", %{pid: pid, opts: opts} do
    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_1",
      repo_id: "repo_seed"
    })

    request = RequestGenerator.build(:write_workspace_file, pid, opts)

    assert request.operation_id == "writeWorkspaceFile"
    assert request.path =~ "/api/v1/workspaces/ws_1/files"
    assert request.body["content"] =~ "release"
    assert request.state_effect.path =~ "workspace/generated/"
  end

  test "sustained random candidates exclude controlled workspace lifecycle operations", %{
    pid: pid,
    opts: opts
  } do
    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_1",
      repo_id: "repo_seed"
    })

    candidates =
      RequestGenerator.candidates(pid, %{opts | include_destructive: true})
      |> Enum.map(&elem(&1, 0))

    refute :commit_workspace in candidates
    refute :close_workspace in candidates
    assert :write_workspace_file in candidates
  end

  test "workspace operations fall back to setup when concurrent state disappears", %{
    pid: pid,
    opts: opts
  } do
    request = RequestGenerator.build(:write_workspace_file, pid, opts)

    assert request.operation_id == "createWorkspace"
    assert request.path == "/api/v1/repos/repo_seed/workspaces"
  end

  test "commit falls back to a write when no workspace has pending changes", %{
    pid: pid,
    opts: opts
  } do
    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_clean",
      repo_id: "repo_seed"
    })

    request = RequestGenerator.build(:commit_workspace, pid, opts)

    assert request.operation_id == "writeWorkspaceFile"
    assert request.path =~ "/api/v1/workspaces/ws_clean/files"
  end

  test "graph reads fall back to refresh until a repo has graph state", %{pid: pid, opts: opts} do
    request = RequestGenerator.build(:query_graph, pid, opts)

    assert request.operation_id == "refreshRepositoryGraph"
    assert request.state_effect.kind == :graph_refreshed
  end
end
