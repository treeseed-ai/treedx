defmodule TreeDx.CacheTest do
  use ExUnit.Case, async: false

  alias TreeDx.Cache

  @table __MODULE__.Table

  setup do
    Cache.ensure_table(@table)
    Cache.reset(@table)
    :ok
  end

  test "tracks approximate bytes and evicts by byte budget" do
    Cache.put(@table, :a, String.duplicate("a", 100), 1, 10, nil)
    Cache.put(@table, :b, String.duplicate("b", 100), 2, 10, nil)

    assert Cache.stats(@table).entries == 2
    assert Cache.stats(@table).approx_bytes > 0

    Cache.evict(@table, %{max_entries: nil, max_bytes: 1})

    assert Cache.stats(@table).entries == 0
  end

  test "an exhausted zero byte budget retains no values while preserving loader results" do
    assert {:ok, "loaded"} =
             Cache.get_or_load(@table, :zero, 1_000, 10, 0, fn -> {:ok, "loaded"} end)

    assert Cache.stats(@table) == %{entries: 0, approx_bytes: 0}
  end

  test "uses byte-budget eviction unless an entry limit is explicitly configured" do
    name = "TREEDX_TEST_CACHE_MAX_ENTRIES"
    System.delete_env(name)
    on_exit(fn -> System.delete_env(name) end)

    assert Cache.entry_limit(name, 256, nil) == 256
    assert Cache.entry_limit(name, 256, 1_000_000) == nil

    System.put_env(name, "512")
    assert Cache.entry_limit(name, 256, 1_000_000) == 512
  end

  test "byte overrides can only lower their finite RAM allocation" do
    name = "TREEDX_TEST_CACHE_MAX_BYTES"
    previous = System.get_env(name)

    on_exit(fn ->
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end)

    for value <- [nil, "", "invalid", "-1", "4096garbage", "1.5", "Infinity"] do
      if value, do: System.put_env(name, value), else: System.delete_env(name)
      assert Cache.byte_limit(name, 4096) == 4096
      assert Cache.byte_limit(name, 0) == 0
    end

    for {value, expected} <- [{"0", 0}, {"1", 1}, {"4096", 4096}, {"4294967296", 4096}] do
      System.put_env(name, value)
      assert Cache.byte_limit(name, 4096) == expected
      assert Cache.byte_limit(name, 0) == 0
    end

    for invalid <- [nil, -1, 1.5, "4096"] do
      assert_raise FunctionClauseError, fn -> Cache.byte_limit(name, invalid) end
    end
  end

  test "get_or_load returns cached value and refreshes last accessed metadata" do
    assert {:ok, "value"} =
             Cache.get_or_load(@table, :key, 1_000, 10, 10_000, fn -> {:ok, "value"} end)

    assert {:ok, "value"} =
             Cache.get_or_load(@table, :key, 1_000, 10, 10_000, fn -> {:ok, "other"} end)
  end

  test "coalesces concurrent loaders for the same cache key" do
    counter = :counters.new(1, [])

    tasks =
      for _ <- 1..12 do
        Task.async(fn ->
          Cache.get_or_load(@table, :shared, 1_000, 10, 10_000, fn ->
            :counters.add(counter, 1, 1)
            Process.sleep(25)
            {:ok, "shared-value"}
          end)
        end)
      end

    assert Enum.map(tasks, &Task.await/1) == List.duplicate({:ok, "shared-value"}, 12)
    assert :counters.get(counter, 1) == 1
  end
end
