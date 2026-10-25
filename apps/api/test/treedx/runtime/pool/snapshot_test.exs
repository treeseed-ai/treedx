defmodule TreeDx.Runtime.Pool.SnapshotTest do
  use ExUnit.Case, async: false

  alias TreeDx.Runtime.Pool
  alias TreeDx.Observability.Metrics

  test "returned work has already released its slot and recorded completion" do
    priority = Process.flag(:priority, :high)

    try do
      for result <- 1..64 do
        :sys.get_state(Pool)
        before = Pool.pool_snapshot(:repository_query)
        count = completed_count()

        assert ^result = Pool.run(:repository_query, fn -> result end)

        after_run = Pool.pool_snapshot(:repository_query)
        assert after_run.active == before.active
        assert after_run.completed == before.completed + 1
        assert completed_count() == count + 1
      end
    after
      Process.flag(:priority, priority)
    end
  end

  defp completed_count do
    metric_count("treedx_pool_completed_total")
  end

  defp metric_count(name) do
    Metrics.snapshot().counters
    |> Enum.filter(&(&1.name == name and &1.labels["pool"] == "repository_query"))
    |> Enum.map(& &1.value)
    |> Enum.sum()
  end

  test "failed and expired work is observable before the failure reply" do
    priority = Process.flag(:priority, :high)

    try do
      for {work, options, code, field, metric} <- [
            {fn -> raise "work failed" end, [], "internal_error", :completed,
             "treedx_pool_completed_total"},
            {fn -> Process.exit(self(), :kill) end, [], "internal_error", :completed,
             "treedx_pool_completed_total"},
            {fn ->
               receive do
                 :never -> :unreachable
               end
             end, [execution_timeout_ms: 1], "server_busy", :executionTimeouts,
             "treedx_pool_execution_timeouts_total"}
          ] do
        :sys.get_state(Pool)
        before = Pool.pool_snapshot(:repository_query)
        count = metric_count(metric)

        assert {:error, %{code: ^code}} = Pool.run(:repository_query, work, options)

        after_run = Pool.pool_snapshot(:repository_query)
        assert after_run.active == before.active
        assert Map.fetch!(after_run, field) == Map.fetch!(before, field) + 1
        assert metric_count(metric) == count + 1
      end
    after
      Process.flag(:priority, priority)
    end
  end

  test "a queued timeout is removed and counted before its failure reply" do
    :sys.get_state(Pool)
    parent = self()
    size = Pool.pool_snapshot(:repository_query).size

    workers =
      for _ <- 1..size do
        Task.async(fn ->
          Pool.run(:repository_query, fn ->
            send(parent, {:admitted, self()})

            receive do
              :finish -> :finished
            end
          end)
        end)
      end

    pids =
      for _ <- 1..size do
        assert_receive {:admitted, pid}
        pid
      end

    :sys.get_state(Pool)
    priority = Process.flag(:priority, :high)

    try do
      before = Pool.pool_snapshot(:repository_query)
      assert before.active == size
      count = metric_count("treedx_pool_queue_timeouts_total")

      assert {:error, %{details: %{reason: "queue_timeout"}}} =
               Pool.run(:repository_query, fn -> flunk("expired queued work ran") end,
                 queue_timeout_ms: 1
               )

      after_run = Pool.pool_snapshot(:repository_query)
      assert after_run.active == before.active
      assert after_run.queueDepth == 0
      assert after_run.queueTimeouts == before.queueTimeouts + 1
      assert metric_count("treedx_pool_queue_timeouts_total") == count + 1
    after
      Process.flag(:priority, priority)
      Enum.each(pids, &send(&1, :finish))
      Enum.each(workers, &assert(:finished == Task.await(&1)))
    end
  end

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
