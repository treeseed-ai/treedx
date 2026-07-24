defmodule TreeDxProfiler.PortfolioStateTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.{Fixtures, PortfolioState}

  test "tracks portfolio repositories, workspaces, and growth counters" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-state-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "state-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "state-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "state-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_initial_repos: 1,
      portfolio_min_repo_age_before_delete: 0,
      portfolio_repo_prefix: "profile-"
    }

    {:ok, pid} = PortfolioState.start_link(opts)
    assert %{repos: [%{repo_id: "repo_seed"}]} = PortfolioState.snapshot(pid)

    assert :ok =
             PortfolioState.apply_effect(pid, %{
               kind: :workspace_created,
               workspace_id: "ws_1",
               repo_id: "repo_seed"
             })

    assert %{active_workspaces: [%{workspace_id: "ws_1"}]} = PortfolioState.snapshot(pid)

    assert :ok =
             PortfolioState.apply_effect(pid, %{
               kind: :file_written,
               workspace_id: "ws_1",
               path: "workspace/generated/doc.md",
               content: "release"
             })

    assert get_in(PortfolioState.snapshot(pid), [:final, "filesGenerated"]) == 1
    File.rm_rf!(root)
  end

  test "stale workspace effects do not insert nil workspace entries" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-state-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "state-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "state-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "state-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_initial_repos: 1,
      portfolio_min_repo_age_before_delete: 0,
      portfolio_repo_prefix: "profile-"
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    assert :ok =
             PortfolioState.apply_effect(pid, %{
               kind: :file_written,
               workspace_id: "ws_missing",
               path: "workspace/generated/doc.md",
               content: "release"
             })

    assert PortfolioState.snapshot(pid).active_workspaces == []
    assert PortfolioState.choose_dirty_workspace(pid) == nil

    File.rm_rf!(root)
  end

  test "workspace selection ignores repos with an active commit reservation" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-state-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "state-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "state-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "state-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_initial_repos: 1,
      portfolio_min_repo_age_before_delete: 0,
      portfolio_repo_prefix: "profile-"
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    PortfolioState.apply_effect(pid, %{
      kind: :workspace_created,
      workspace_id: "ws_1",
      repo_id: "repo_seed"
    })

    PortfolioState.apply_effect(pid, %{
      kind: :file_written,
      workspace_id: "ws_1",
      path: "workspace/generated/doc.md",
      content: "release"
    })

    assert %{workspace_id: "ws_1"} = PortfolioState.reserve_dirty_workspace(pid)
    assert PortfolioState.choose_workspace(pid) == nil
    assert PortfolioState.choose_mutable_repo(pid) == nil

    PortfolioState.apply_effect(pid, %{kind: :workspace_commit_finished, workspace_id: "ws_1"})

    assert %{workspace_id: "ws_1"} = PortfolioState.choose_workspace(pid)
    assert %{repo_id: "repo_seed"} = PortfolioState.choose_mutable_repo(pid)

    File.rm_rf!(root)
  end

  test "snapshot reservation excludes mutable repository selection until released" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-state-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "state-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "state-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "state-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_initial_repos: 1,
      portfolio_min_repo_age_before_delete: 0,
      portfolio_repo_prefix: "profile-"
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    assert %{repo_id: "repo_seed"} = PortfolioState.reserve_snapshot_repo(pid)
    assert PortfolioState.choose_mutable_repo(pid) == nil

    PortfolioState.apply_effect(pid, %{kind: :snapshot_finished, repo_id: "repo_seed"})

    assert %{repo_id: "repo_seed"} = PortfolioState.choose_mutable_repo(pid)

    File.rm_rf!(root)
  end

  test "workspace creation reservation excludes repo until released" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-state-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: "state-test",
        repo_prefix: "profile-",
        fixture_root: root,
        size: "small",
        seed: "state-seed"
      )

    fixture = %{fixture | local_repos: [Map.put(hd(fixture.local_repos), :repo_id, "repo_seed")]}

    opts = %{
      fixture: fixture,
      profile_id: "state-test",
      fixture_root: root,
      size: "small",
      portfolio_max_repos: 10,
      portfolio_initial_repos: 1,
      portfolio_min_repo_age_before_delete: 0,
      portfolio_repo_prefix: "profile-"
    }

    {:ok, pid} = PortfolioState.start_link(opts)

    assert %{repo_id: "repo_seed"} = PortfolioState.reserve_workspace_repo(pid)
    assert PortfolioState.choose_mutable_repo(pid) == nil
    assert PortfolioState.reserve_workspace_repo(pid) == nil

    PortfolioState.apply_effect(pid, %{kind: :workspace_create_finished, repo_id: "repo_seed"})

    assert %{repo_id: "repo_seed"} = PortfolioState.choose_mutable_repo(pid)

    File.rm_rf!(root)
  end
end
