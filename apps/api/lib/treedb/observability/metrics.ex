defmodule TreeDb.Observability.Metrics do
  @moduledoc false
  use GenServer

  alias TreeDb.Observability.Scrubber

  @buckets [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, :infinity]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    {:ok, %{counters: %{}, histograms: %{}, gauges: %{}}}
  end

  def incr(name, labels \\ %{}, value \\ 1),
    do: call_or_ignore({:incr, to_string(name), Scrubber.scrub_labels(labels), value})

  def observe(name, value, labels \\ %{}),
    do: call_or_ignore({:observe, to_string(name), value, Scrubber.scrub_labels(labels)})

  def put_gauge(name, value, labels \\ %{}),
    do: call_or_ignore({:put_gauge, to_string(name), value, Scrubber.scrub_labels(labels)})

  def record_audit_event(event_type, attrs \\ %{}) do
    status = safe_status(attrs)
    data = attrs[:data] || attrs["data"] || %{}

    case metric_for_event(to_string(event_type)) do
      nil ->
        :ok

      {name, labels} ->
        incr(name, Map.merge(labels, %{status: status}))
    end

    maybe_observe_duration(event_type, data)
    maybe_record_bytes(event_type, data)
    maybe_record_partial_failure(event_type, data)
  end

  def snapshot, do: call_or_default(:snapshot, empty_snapshot())
  def prometheus, do: snapshot() |> render_prometheus()
  def reset!, do: call_or_ignore(:reset)

  defp metric_for_event("repo." <> rest),
    do: {"treedb_repo_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("git." <> rest),
    do:
      {"treedb_git_remote_operations_total", %{operation: event_operation(rest), backend: "git"}}

  defp metric_for_event("workspace." <> rest),
    do: {"treedb_workspace_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("exec." <> rest),
    do: {"treedb_exec_runs_total", %{operation: event_operation(rest), backend: "configured"}}

  defp metric_for_event("graph.refreshed"),
    do: {"treedb_graph_refresh_total", %{operation: "refresh"}}

  defp metric_for_event("repo.query_executed"),
    do: {"treedb_repo_operations_total", %{operation: "query"}}

  defp metric_for_event("repo.files_searched"),
    do: {"treedb_repo_operations_total", %{operation: "search"}}

  defp metric_for_event("context." <> rest),
    do: {"treedb_repo_operations_total", %{operation: "context_" <> event_operation(rest)}}

  defp metric_for_event("search.index_" <> rest),
    do: {"treedb_search_index_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("snapshot." <> rest),
    do: {"treedb_snapshot_build_total", %{operation: event_operation(rest)}}

  defp metric_for_event("artifact." <> rest),
    do: {"treedb_artifact_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("mirror.sync" <> _),
    do: {"treedb_mirror_sync_total", %{operation: "sync"}}

  defp metric_for_event("federated." <> rest),
    do: {"treedb_federated_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("storage." <> rest),
    do: {"treedb_storage_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event(_event), do: nil

  defp maybe_observe_duration(event_type, data) do
    duration = data[:elapsedMs] || data["elapsedMs"] || data[:durationMs] || data["durationMs"]

    if is_number(duration) do
      case to_string(event_type) do
        "exec." <> _ -> observe("treedb_exec_duration_ms", duration, %{backend: "configured"})
        "graph.refreshed" -> observe("treedb_graph_refresh_duration_ms", duration)
        "repo.query_executed" -> observe("treedb_query_duration_ms", duration)
        "context.built" -> observe("treedb_context_build_duration_ms", duration)
        "storage.check" <> _ -> observe("treedb_storage_check_duration_ms", duration)
        "storage.compact" <> _ -> observe("treedb_storage_compaction_duration_ms", duration)
        "snapshot." <> _ -> observe("treedb_snapshot_duration_ms", duration)
        _ -> :ok
      end
    end
  end

  defp maybe_record_bytes(event_type, data) do
    bytes = data[:byteLength] || data["byteLength"] || data[:bytes] || data["bytes"]

    if is_number(bytes) and String.starts_with?(to_string(event_type), "snapshot.") do
      incr("treedb_snapshot_bytes_total", %{}, bytes)
    end
  end

  defp maybe_record_partial_failure(event_type, data) do
    count = data[:partialFailureCount] || data["partialFailureCount"] || 0

    if count > 0 and String.starts_with?(to_string(event_type), "federated.") do
      incr(
        "treedb_federated_partial_failures_total",
        %{operation: event_operation(event_type)},
        count
      )
    end
  end

  defp safe_status(attrs), do: to_string(attrs[:status] || attrs["status"] || "ok")
  defp event_operation(event), do: event |> to_string() |> String.split(".") |> List.last()

  def handle_call({:incr, name, labels, value}, _from, state) do
    key = {name, labels}
    counters = Map.update(state.counters, key, value, &(&1 + value))
    {:reply, :ok, %{state | counters: counters}}
  end

  def handle_call({:observe, name, value, labels}, _from, state) do
    key = {name, labels}

    histograms =
      Map.update(state.histograms, key, new_histogram(value), fn histogram ->
        update_histogram(histogram, value)
      end)

    {:reply, :ok, %{state | histograms: histograms}}
  end

  def handle_call({:put_gauge, name, value, labels}, _from, state) do
    {:reply, :ok, %{state | gauges: Map.put(state.gauges, {name, labels}, value)}}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, materialize(state), state}

  def handle_call(:reset, _from, _state),
    do: {:reply, :ok, %{counters: %{}, histograms: %{}, gauges: %{}}}

  defp call_or_ignore(message) do
    call_or_default(message, :ok)
  end

  defp call_or_default(message, default) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, message)
    else
      default
    end
  end

  defp new_histogram(value),
    do: update_histogram(%{buckets: initial_buckets(), sum: 0, count: 0}, value)

  defp update_histogram(histogram, value) do
    buckets =
      Enum.reduce(@buckets, histogram.buckets, fn bucket, acc ->
        if bucket == :infinity or value <= bucket do
          Map.update!(acc, bucket, &(&1 + 1))
        else
          acc
        end
      end)

    %{histogram | buckets: buckets, sum: histogram.sum + value, count: histogram.count + 1}
  end

  defp initial_buckets, do: Map.new(@buckets, &{&1, 0})

  defp materialize(state) do
    %{
      counters:
        entries(state.counters, fn {name, labels}, value ->
          %{name: name, labels: labels, value: value}
        end),
      histograms:
        entries(state.histograms, fn {name, labels}, histogram ->
          %{
            name: name,
            labels: labels,
            buckets:
              Enum.map(@buckets, fn bucket ->
                %{
                  le: if(bucket == :infinity, do: "+Inf", else: bucket),
                  value: histogram.buckets[bucket]
                }
              end),
            sum: histogram.sum,
            count: histogram.count
          }
        end),
      gauges:
        entries(state.gauges, fn {name, labels}, value ->
          %{name: name, labels: labels, value: value}
        end)
    }
  end

  defp entries(map, mapper) do
    map
    |> Enum.map(fn {key, value} -> mapper.(key, value) end)
    |> Enum.sort_by(&{&1.name, inspect(&1.labels)})
  end

  defp empty_snapshot, do: %{counters: [], histograms: [], gauges: []}

  defp render_prometheus(snapshot) do
    [
      Enum.map(snapshot.counters, fn entry ->
        [
          "# HELP #{entry.name} TreeDB counter.\n",
          "# TYPE #{entry.name} counter\n",
          "#{entry.name}#{labels(entry.labels)} #{entry.value}\n"
        ]
      end),
      Enum.map(snapshot.gauges, fn entry ->
        [
          "# HELP #{entry.name} TreeDB gauge.\n",
          "# TYPE #{entry.name} gauge\n",
          "#{entry.name}#{labels(entry.labels)} #{entry.value}\n"
        ]
      end),
      Enum.map(snapshot.histograms, fn entry ->
        base = [
          "# HELP #{entry.name} TreeDB histogram.\n",
          "# TYPE #{entry.name} histogram\n"
        ]

        buckets =
          Enum.map(entry.buckets, fn bucket ->
            bucket_labels = Map.put(entry.labels, "le", bucket.le)
            "#{entry.name}_bucket#{labels(bucket_labels)} #{bucket.value}\n"
          end)

        base ++
          buckets ++
          [
            "#{entry.name}_sum#{labels(entry.labels)} #{entry.sum}\n",
            "#{entry.name}_count#{labels(entry.labels)} #{entry.count}\n"
          ]
      end)
    ]
    |> IO.iodata_to_binary()
  end

  defp labels(labels) when map_size(labels) == 0, do: ""

  defp labels(labels) do
    rendered =
      labels
      |> Enum.sort()
      |> Enum.map(fn {key, value} -> "#{key}=#{inspect(escape_label(value))}" end)
      |> Enum.join(",")

    "{#{rendered}}"
  end

  defp escape_label(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\"", "\\\"")
  end
end
