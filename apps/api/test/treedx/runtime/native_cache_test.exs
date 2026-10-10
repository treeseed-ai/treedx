defmodule TreeDx.Runtime.NativeCacheTest do
  use ExUnit.Case, async: false

  test "actual repository and native graph caches cannot override an exhausted shared RAM allocation" do
    names = ~w(TREEDX_RUNTIME_MEMORY_BUDGET_MB TREEDX_REPO_DOC_CACHE_MAX_BYTES TREEDX_GRAPH_INDEX_CACHE_MAX_BYTES)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    manager = Process.whereis(TreeDx.Cache.Manager)
    :ok = :sys.suspend(manager)

    on_exit(fn ->
      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)

      TreeDx.RepositoryCache.reset!()
      TreeDx.Graph.IndexCache.reset!()
      :ok = :sys.resume(manager)
    end)

    System.put_env("TREEDX_RUNTIME_MEMORY_BUDGET_MB", "256")
    System.put_env("TREEDX_REPO_DOC_CACHE_MAX_BYTES", "4294967296")
    System.put_env("TREEDX_GRAPH_INDEX_CACHE_MAX_BYTES", "4294967296")
    TreeDx.RepositoryCache.reset!()
    TreeDx.Graph.IndexCache.reset!()
    assert TreeDx.Runtime.Resources.cache_budget_bytes() == 0
    assert {:ok, index} = TreeDx.Graph.Native.build_graph_index(%{
      "repoId" => "bounded-native-cache", "refName" => "refs/heads/main",
      "commitSha" => String.duplicate("a", 40), "documents" => []
    })

    for n <- 1..2 do
      assert {:ok, %{iteration: ^n}} = TreeDx.RepositoryCache.context("bounded-repo", "main", fn -> {:ok, %{iteration: n}} end)
      assert {:ok, observed} = TreeDx.Graph.IndexCache.get_or_load("bounded-graph", "version", fn -> {:ok, Map.put(index, "iteration", n)} end)
      assert observed["iteration"] == n
      assert is_reference(observed.native_resource)
      assert TreeDx.Cache.stats(TreeDx.RepositoryCache) == %{entries: 0, approx_bytes: 0}
      assert TreeDx.Cache.stats(TreeDx.Graph.IndexCache) == %{entries: 0, approx_bytes: 0}
    end
  end

  test "actual NIF catalog writes and independent readback survive cache exhaustion and reconfiguration" do
    dir =
      Path.join(System.tmp_dir!(), "treedx-native-cache-#{System.unique_integer([:positive])}")

    manager = Process.whereis(TreeDx.Cache.Manager)
    assert is_pid(manager)
    :ok = :sys.suspend(manager)

    previous = Application.get_env(:treedx, :data_dir)
    {_count, _bytes, budget} = TreeDx.Native.log_cache_stats()

    on_exit(fn ->
      TreeDx.Native.configure_log_cache(budget)
      Application.put_env(:treedx, :data_dir, previous)
      File.rm_rf!(dir)
      :ok = :sys.resume(manager)
    end)

    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Native.configure_log_cache(8192)

    for invalid <- [-1, "4096", nil] do
      assert_raise ArgumentError, fn -> TreeDx.Native.configure_log_cache(invalid) end
      assert {_count, _bytes, 8192} = TreeDx.Native.log_cache_stats()
    end

    TreeDx.Store.init!(node_id: "native_cache_node")

    records =
      for n <- 1..24 do
        {:ok, record} =
          TreeDx.Store.put_repository(%{
            "name" => "cache-#{n}",
            "localPath" => Path.join(dir, "repo-#{n}"),
            "remoteUrl" => "https://example.invalid/" <> String.duplicate("x", 1024)
          })

        {_count, bytes, 8192} = TreeDx.Native.log_cache_stats()
        assert bytes <= 8192
        record
      end

    for record <- records do
      assert {:ok, ^record} = TreeDx.Store.get_repository(record["id"])
    end

    assert {0, 0, 0} = TreeDx.Native.configure_log_cache(0)
    assert {:ok, listed} = TreeDx.Store.list_repositories()
    assert Enum.sort_by(listed, & &1["id"]) == Enum.sort_by(records, & &1["id"])
    assert {0, 0, 0} = TreeDx.Native.log_cache_stats()
  end
end
