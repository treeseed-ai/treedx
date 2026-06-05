defmodule TreeDb.Runtime.Pool do
  @moduledoc false
  use GenServer

  alias TreeDb.Observability.Metrics
  alias TreeDb.Runtime.Resources

  @pools [:repository_query, :workspace_mutation, :graph, :snapshot, :import]
  @priorities [:high, :normal, :low]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    state = Map.new(@pools, &{&1, new_pool(&1)})
    publish(state)
    {:ok, state}
  end

  def run(pool, fun, opts \\ []) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:run, pool, fun, opts}, :infinity)
  end

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  def pool_snapshot(pool), do: Map.get(snapshot(), pool) || Map.get(snapshot(), to_string(pool))

  def pressure(pool) do
    case pool_snapshot(pool) do
      nil -> :unknown
      info -> pressure_for(info)
    end
  end

  def saturated?(pool), do: pressure(pool) == :saturated
  def available?(pool), do: pressure(pool) in [:low, :moderate]

  def handle_call(:snapshot, _from, state), do: {:reply, materialize(state), state}

  def handle_call({:run, pool, fun, opts}, from, state) do
    pool = normalize_pool(pool)
    info = Map.fetch!(state, pool)
    job = new_job(pool, fun, opts, from)

    cond do
      map_size(info.active) < info.size ->
        {info, _job} = start_job(info, job)
        state = put_and_publish(state, pool, info)
        {:noreply, state}

      info.queue_depth < info.queue_max ->
        info = enqueue(info, job)
        state = put_and_publish(state, pool, info)
        {:noreply, state}

      true ->
        info = %{info | rejected: info.rejected + 1}

        Metrics.incr("treedb_pool_rejections_total", %{
          pool: to_string(pool),
          reason: "queue_full"
        })

        state = put_and_publish(state, pool, info)
        {:reply, busy(pool, "queue_full"), state}
    end
  end

  def handle_info({:queue_timeout, pool, job_id}, state) do
    pool = normalize_pool(pool)
    info = Map.fetch!(state, pool)

    case dequeue_job(info, job_id) do
      {nil, info} ->
        {:noreply, put_and_publish(state, pool, info)}

      {job, info} ->
        cancel_timer(job.timeout_ref)
        demonitor(job.caller_monitor_ref)
        GenServer.reply(job.from, busy(pool, "queue_timeout"))
        info = %{info | queue_timeouts: info.queue_timeouts + 1}
        Metrics.incr("treedb_pool_queue_timeouts_total", %{pool: to_string(pool)})
        {:noreply, put_and_publish(state, pool, info)}
    end
  end

  def handle_info({:execution_timeout, pool, task_ref}, state) do
    pool = normalize_pool(pool)
    info = Map.fetch!(state, pool)

    case Map.pop(info.active, task_ref) do
      {nil, _active} ->
        {:noreply, state}

      {job, active} ->
        if job.task_pid,
          do: Task.Supervisor.terminate_child(TreeDb.Runtime.Pool.TaskSupervisor, job.task_pid)

        demonitor(job.caller_monitor_ref)
        GenServer.reply(job.from, busy(pool, "execution_timeout"))

        info =
          %{info | active: active, execution_timeouts: info.execution_timeouts + 1}
          |> maybe_start_next()

        Metrics.incr("treedb_pool_execution_timeouts_total", %{pool: to_string(pool)})
        {:noreply, put_and_publish(state, pool, info)}
    end
  end

  def handle_info({task_ref, result}, state) when is_reference(task_ref) do
    Process.demonitor(task_ref, [:flush])

    case find_active(state, task_ref) do
      nil ->
        {:noreply, state}

      {pool, info, job} ->
        cancel_timer(job.execution_timeout_ref)
        demonitor(job.caller_monitor_ref)
        execution_ms = System.monotonic_time(:millisecond) - job.started_at
        Metrics.observe("treedb_pool_execution_ms", execution_ms, %{pool: to_string(pool)})
        GenServer.reply(job.from, result)

        info =
          %{
            info
            | active: Map.delete(info.active, task_ref),
              completed: info.completed + 1,
              total_execution_ms: info.total_execution_ms + execution_ms
          }
          |> maybe_start_next()

        Metrics.incr("treedb_pool_completed_total", %{pool: to_string(pool)})
        {:noreply, put_and_publish(state, pool, info)}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_by_caller_monitor(state, ref) do
      {:queued, pool, info, job} ->
        cancel_timer(job.timeout_ref)

        info =
          info
          |> remove_job(job.id)
          |> Map.update!(:cancelled, &(&1 + 1))

        Metrics.incr("treedb_pool_cancelled_total", %{pool: to_string(pool), state: "queued"})
        {:noreply, put_and_publish(state, pool, info)}

      {:active, pool, info, job, task_ref} ->
        if job.task_pid,
          do: Task.Supervisor.terminate_child(TreeDb.Runtime.Pool.TaskSupervisor, job.task_pid)

        cancel_timer(job.execution_timeout_ref)

        info =
          %{
            info
            | active: Map.delete(info.active, task_ref),
              cancelled: info.cancelled + 1
          }
          |> maybe_start_next()

        Metrics.incr("treedb_pool_cancelled_total", %{pool: to_string(pool), state: "active"})
        {:noreply, put_and_publish(state, pool, info)}

      nil ->
        case find_active(state, ref) do
          nil ->
            {:noreply, state}

          {pool, info, job} ->
            cancel_timer(job.execution_timeout_ref)
            demonitor(job.caller_monitor_ref)
            GenServer.reply(job.from, task_failed(reason))

            info =
              %{
                info
                | active: Map.delete(info.active, ref),
                  completed: info.completed + 1
              }
              |> maybe_start_next()

            Metrics.incr("treedb_pool_completed_total", %{pool: to_string(pool), status: "crash"})
            {:noreply, put_and_publish(state, pool, info)}
        end
    end
  end

  defp new_pool(pool) do
    %{
      size: Resources.worker_pool_size(pool),
      active: %{},
      queues: Map.new(@priorities, &{&1, :queue.new()}),
      queue_depth: 0,
      queue_max: Resources.worker_pool_max_queue(pool),
      active_max: 0,
      queue_depth_max: 0,
      enqueued: 0,
      started: 0,
      completed: 0,
      rejected: 0,
      queue_timeouts: 0,
      execution_timeouts: 0,
      cancelled: 0,
      total_wait_ms: 0,
      total_execution_ms: 0
    }
  end

  defp new_job(pool, fun, opts, from) do
    now = System.monotonic_time(:millisecond)

    queue_timeout_ms =
      Keyword.get(opts, :queue_timeout_ms) || Resources.worker_pool_queue_timeout(pool)

    priority = Keyword.get(opts, :priority, :normal)

    execution_timeout_ms =
      Keyword.get(opts, :execution_timeout_ms) || Resources.execution_timeout_ms()

    {caller_pid, _tag} = from

    %{
      id: "pool_job_#{System.unique_integer([:positive])}",
      pool: pool,
      from: from,
      fun: fun,
      priority: if(priority in @priorities, do: priority, else: :normal),
      enqueued_at: now,
      deadline_at: now + queue_timeout_ms,
      queue_timeout_ms: queue_timeout_ms,
      execution_timeout_ms: execution_timeout_ms,
      timeout_ref: nil,
      execution_timeout_ref: nil,
      caller_monitor_ref: Process.monitor(caller_pid),
      task_ref: nil,
      task_pid: nil,
      started_at: nil
    }
  end

  defp enqueue(info, job) do
    timeout_ref =
      Process.send_after(self(), {:queue_timeout, job.pool, job.id}, job.queue_timeout_ms)

    job = %{job | timeout_ref: timeout_ref}
    queue = Map.fetch!(info.queues, job.priority)

    info
    |> put_in([:queues, job.priority], :queue.in(job, queue))
    |> Map.update!(:queue_depth, &(&1 + 1))
    |> Map.update!(:queue_depth_max, &max(&1, info.queue_depth + 1))
    |> Map.update!(:enqueued, &(&1 + 1))
    |> tap(fn _ -> Metrics.incr("treedb_pool_enqueued_total", %{pool: to_string(job.pool)}) end)
  end

  defp start_job(info, job) do
    cancel_timer(job.timeout_ref)
    wait_ms = System.monotonic_time(:millisecond) - job.enqueued_at
    Metrics.observe("treedb_pool_wait_ms", wait_ms, %{pool: to_string(job.pool)})

    task = Task.Supervisor.async_nolink(TreeDb.Runtime.Pool.TaskSupervisor, job.fun)
    execution_timeout_ref = maybe_execution_timeout(job.pool, task.ref, job.execution_timeout_ms)

    job = %{
      job
      | task_ref: task.ref,
        task_pid: task.pid,
        started_at: System.monotonic_time(:millisecond),
        execution_timeout_ref: execution_timeout_ref
    }

    info =
      %{
        info
        | active: Map.put(info.active, task.ref, job),
          active_max: max(info.active_max, map_size(info.active) + 1),
          started: info.started + 1,
          total_wait_ms: info.total_wait_ms + wait_ms
      }

    Metrics.incr("treedb_pool_started_total", %{pool: to_string(job.pool)})
    {info, job}
  end

  defp maybe_start_next(info) do
    if map_size(info.active) < info.size and info.queue_depth > 0 do
      case pop_next(info) do
        {nil, info} ->
          info

        {job, info} ->
          {info, _job} = start_job(info, job)
          maybe_start_next(info)
      end
    else
      info
    end
  end

  defp pop_next(info) do
    Enum.reduce_while(@priorities, {nil, info}, fn priority, {_job, acc_info} ->
      queue = Map.fetch!(acc_info.queues, priority)

      case :queue.out(queue) do
        {{:value, job}, queue} ->
          acc_info =
            acc_info
            |> put_in([:queues, priority], queue)
            |> Map.update!(:queue_depth, &max(&1 - 1, 0))

          {:halt, {job, acc_info}}

        {:empty, _queue} ->
          {:cont, {nil, acc_info}}
      end
    end)
  end

  defp dequeue_job(info, job_id) do
    Enum.reduce(@priorities, {nil, info}, fn
      _priority, {job = %{}, acc_info} ->
        {job, acc_info}

      priority, {nil, acc_info} ->
        queue = Map.fetch!(acc_info.queues, priority)
        {found, queue} = take_from_queue(queue, job_id)

        if found do
          {found,
           acc_info
           |> put_in([:queues, priority], queue)
           |> Map.update!(:queue_depth, &max(&1 - 1, 0))}
        else
          {nil, acc_info}
        end
    end)
  end

  defp remove_job(info, job_id), do: elem(dequeue_job(info, job_id), 1)

  defp take_from_queue(queue, job_id) do
    queue
    |> :queue.to_list()
    |> Enum.reduce({nil, :queue.new()}, fn job, {found, acc} ->
      cond do
        found -> {found, :queue.in(job, acc)}
        job.id == job_id -> {job, acc}
        true -> {nil, :queue.in(job, acc)}
      end
    end)
  end

  defp find_active(state, task_ref) do
    Enum.find_value(state, fn {pool, info} ->
      case Map.fetch(info.active, task_ref) do
        {:ok, job} -> {pool, info, job}
        :error -> nil
      end
    end)
  end

  defp find_by_caller_monitor(state, monitor_ref) do
    Enum.find_value(state, fn {pool, info} ->
      active =
        Enum.find_value(info.active, fn {task_ref, job} ->
          if job.caller_monitor_ref == monitor_ref, do: {:active, pool, info, job, task_ref}
        end)

      active ||
        Enum.find_value(@priorities, fn priority ->
          info.queues
          |> Map.fetch!(priority)
          |> :queue.to_list()
          |> Enum.find(&(&1.caller_monitor_ref == monitor_ref))
          |> then(fn
            nil -> nil
            job -> {:queued, pool, info, job}
          end)
        end)
    end)
  end

  defp maybe_execution_timeout(_pool, _task_ref, timeout) when timeout in [nil, 0], do: nil

  defp maybe_execution_timeout(pool, task_ref, timeout),
    do: Process.send_after(self(), {:execution_timeout, pool, task_ref}, timeout)

  defp busy(pool, reason) do
    {:error,
     %{
       code: "server_busy",
       message: "TreeDB is busy processing repository work. Retry later.",
       details: %{
         pool: to_string(pool),
         reason: reason,
         retryAfterMs: 1_000
       }
     }}
  end

  defp task_failed(reason) do
    {:error,
     %{
       code: "internal_error",
       message: "TreeDB failed while processing repository work.",
       details: %{reason: inspect(reason)}
     }}
  end

  defp put_and_publish(state, pool, info) do
    publish_pool(pool, info)
    Map.put(state, pool, info)
  end

  defp publish(state), do: Enum.each(state, fn {pool, info} -> publish_pool(pool, info) end)

  defp publish_pool(pool, info) do
    labels = %{pool: to_string(pool)}
    Metrics.put_gauge("treedb_pool_active", map_size(info.active), labels)
    Metrics.put_gauge("treedb_pool_size", info.size, labels)
    Metrics.put_gauge("treedb_pool_active_max", info.active_max, labels)
    Metrics.put_gauge("treedb_pool_queue_depth", info.queue_depth, labels)
    Metrics.put_gauge("treedb_pool_queue_depth_max", info.queue_depth_max, labels)
    Metrics.put_gauge("treedb_pool_queue_max", info.queue_max, labels)
    Metrics.put_gauge("treedb_pool_pressure", pressure_value(pressure_for(info)), labels)
    Metrics.put_gauge("treedb_pool_rejections_total", info.rejected, labels)
    Metrics.put_gauge("treedb_pool_queue_timeouts_total", info.queue_timeouts, labels)
    Metrics.put_gauge("treedb_pool_execution_timeouts_total", info.execution_timeouts, labels)
  end

  defp materialize(state), do: Map.new(state, fn {pool, info} -> {pool, public_info(info)} end)

  defp public_info(info) do
    %{
      size: info.size,
      active: map_size(info.active),
      queueDepth: info.queue_depth,
      queueMax: info.queue_max,
      activeMax: info.active_max,
      queueDepthMax: info.queue_depth_max,
      enqueued: info.enqueued,
      started: info.started,
      completed: info.completed,
      rejected: info.rejected,
      queueTimeouts: info.queue_timeouts,
      executionTimeouts: info.execution_timeouts,
      cancelled: info.cancelled,
      availableSlots: max(info.size - map_size(info.active), 0),
      pressure: to_string(pressure_for(info)),
      totalWaitMs: info.total_wait_ms,
      totalExecutionMs: info.total_execution_ms
    }
  end

  defp pressure_for(%{active: active, size: size, queue_depth: queue_depth, queue_max: queue_max}) do
    active_ratio = safe_ratio(map_size(active), size)
    queue_ratio = safe_ratio(queue_depth, queue_max)

    cond do
      queue_ratio >= 0.9 -> :saturated
      active_ratio >= 0.9 or queue_ratio >= 0.6 -> :high
      active_ratio >= 0.7 or queue_ratio >= 0.25 -> :moderate
      true -> :low
    end
  end

  defp safe_ratio(_value, max) when max in [nil, 0], do: 0.0
  defp safe_ratio(value, max), do: value / max
  defp pressure_value(:low), do: 0
  defp pressure_value(:moderate), do: 1
  defp pressure_value(:high), do: 2
  defp pressure_value(:saturated), do: 3
  defp pressure_value(_), do: -1

  defp normalize_pool(pool) when is_atom(pool), do: pool
  defp normalize_pool(pool), do: pool |> to_string() |> String.to_existing_atom()

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp demonitor(nil), do: :ok
  defp demonitor(ref), do: Process.demonitor(ref, [:flush])
end
