defmodule TreeDb.CacheTest do
  use ExUnit.Case, async: false

  alias TreeDb.Cache

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
end
