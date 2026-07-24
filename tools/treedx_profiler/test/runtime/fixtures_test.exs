defmodule TreeDxProfiler.FixturesTest do
  use ExUnit.Case, async: false

  alias TreeDxProfiler.Fixtures

  test "every canonical fixture supports every size" do
    for fixture <- Fixtures.canonical(), size <- Fixtures.sizes() do
      definition = Fixtures.definition(fixture, size)
      assert definition.id == fixture
      assert definition.size == size
      assert definition.repos > 0
      assert definition.markdown >= 0
    end
  end

  test "old fixture names are rejected" do
    assert_raise RuntimeError, ~r/unknown fixture/, fn ->
      Fixtures.definition("small")
    end
  end

  test "generates deterministic canonical repository fixture and expectations" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-test-#{System.unique_integer([:positive])}")

    profile_id = "profile-test"

    fixture =
      Fixtures.generate!("small-docs",
        profile_id: profile_id,
        fixture_root: root,
        repo_prefix: "test-",
        seed: "fixed",
        size: "small"
      )

    assert fixture.fixture_id == "small-docs"
    assert fixture.repo_prefix == "test-"
    assert fixture.size == "small"
    assert length(fixture.local_repos) == 1
    assert hd(fixture.local_repos).name =~ ~r/^test-small-docs-small-1$/
    assert File.exists?(hd(fixture.local_repos).path)
    assert fixture.expected.repo_count == 1
    assert fixture.expected.file_counts.markdown == 8
    assert fixture.expected.search_hits["release"].exact_generated_hits > 0
    assert fixture.expected.content_hashes != %{}
    assert fixture.expected.graph.min_nodes > 0
    assert fixture.expected.workspace.write_targets != []

    File.rm_rf!(root)
  end

  test "binary fixture records deterministic hashes" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-test-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("binary-assets",
        profile_id: "binary-profile",
        fixture_root: root,
        seed: "fixed",
        size: "small"
      )

    binary_hashes =
      fixture.expected.content_hashes
      |> Enum.filter(fn {path, _} -> String.contains?(path, "assets/") end)

    assert length(binary_hashes) == 8
    assert Enum.all?(binary_hashes, fn {_path, meta} -> byte_size(meta.sha256) == 64 end)

    File.rm_rf!(root)
  end

  test "all fixture combines every canonical family" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-test-#{System.unique_integer([:positive])}")

    fixture =
      Fixtures.generate!("all",
        profile_id: "all-profile",
        fixture_root: root,
        seed: "fixed",
        size: "small"
      )

    assert fixture.fixture_id == "all"
    assert length(fixture.families) == length(Fixtures.canonical())
    assert fixture.expected.repo_count == 6

    File.rm_rf!(root)
  end
end
