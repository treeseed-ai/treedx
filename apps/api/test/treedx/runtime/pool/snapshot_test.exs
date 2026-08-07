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
end
