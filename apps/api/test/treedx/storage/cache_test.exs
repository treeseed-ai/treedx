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
