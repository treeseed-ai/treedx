defmodule TreeDx.Runtime.Pool.SnapshotTest do
  use ExUnit.Case, async: false

  alias TreeDx.Runtime.Pool

  test "pool observations do not wait for the job coordinator" do
    coordinator = Process.whereis(Pool)
    assert is_pid(coordinator)

    :ok = :sys.suspend(coordinator)

    try do
      assert %{size: size, active: active, pressure: pressure} =
               Pool.pool_snapshot(:repository_query)

      assert size > 0
      assert active >= 0
      assert pressure in ["low", "moderate", "high", "saturated"]
      assert Map.has_key?(Pool.snapshot(), :repository_query)
    after
      :ok = :sys.resume(coordinator)
    end
  end

  test "nested work in the same pool executes inside the existing admission" do
    before = Pool.pool_snapshot(:repository_query)

    assert :nested_result ==
             Pool.run(:repository_query, fn ->
               Pool.run(:repository_query, fn -> :nested_result end)
             end)

    after_run = Pool.pool_snapshot(:repository_query)
    assert after_run.started == before.started + 1
  end

  test "nested work preserves pool failure replies" do
    assert {:error, %{code: "internal_error"}} =
             Pool.run(:repository_query, fn ->
               Pool.run(:repository_query, fn -> raise "nested failure" end)
             end)
  end
end
