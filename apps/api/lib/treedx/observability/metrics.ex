defmodule TreeDx.Observability.Metrics do
  @moduledoc false
  use GenServer

  alias TreeDx.Observability.Scrubber

  @buckets [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, :infinity]
  @counter_table TreeDx.Observability.CounterMetrics
  @histogram_table TreeDx.Observability.HistogramMetrics
  @gauge_table TreeDx.Observability.GaugeMetrics
  @scale 1_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    for table <- tables() do
      :ets.new(table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    {:ok, %{}}
  end

  def incr(name, labels \\ %{}, value \\ 1) do
    if table_exists?(@counter_table) do
      key = {to_string(name), Scrubber.scrub_labels(labels)}
      :ets.update_counter(@counter_table, key, {2, value}, {key, 0})
    end

    :ok
  end

  def observe(name, value, labels \\ %{}) do
    if table_exists?(@histogram_table) do
      key = {to_string(name), Scrubber.scrub_labels(labels)}
      :ets.insert_new(@histogram_table, empty_histogram(key))
      :ets.update_counter(@histogram_table, key, histogram_updates(value))
    end

    :ok
  end

  def put_gauge(name, value, labels \\ %{}) do
    if table_exists?(@gauge_table) do
      key = {to_string(name), Scrubber.scrub_labels(labels)}
      :ets.insert(@gauge_table, {key, value})
    end

    :ok
  end

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

  def snapshot do
    if Enum.all?(tables(), &table_exists?/1), do: materialize(), else: empty_snapshot()
  end

  def prometheus, do: snapshot() |> render_prometheus()

  def reset! do
    Enum.each(tables(), fn table ->
      if table_exists?(table), do: :ets.delete_all_objects(table)
    end)

    :ok
  end

  defp metric_for_event("repo." <> rest),
    do: {"treedx_repo_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("git." <> rest),
    do:
      {"treedx_git_remote_operations_total", %{operation: event_operation(rest), backend: "git"}}

  defp metric_for_event("workspace." <> rest),
    do: {"treedx_workspace_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("exec." <> rest),
    do: {"treedx_exec_runs_total", %{operation: event_operation(rest), backend: "configured"}}

  defp metric_for_event("graph.refreshed"),
    do: {"treedx_graph_refresh_total", %{operation: "refresh"}}

  defp metric_for_event("repo.query_executed"),
    do: {"treedx_repo_operations_total", %{operation: "query"}}

  defp metric_for_event("repo.files_searched"),
    do: {"treedx_repo_operations_total", %{operation: "search"}}

  defp metric_for_event("context." <> rest),
    do: {"treedx_repo_operations_total", %{operation: "context_" <> event_operation(rest)}}

  defp metric_for_event("search.index_" <> rest),
    do: {"treedx_search_index_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("snapshot." <> rest),
    do: {"treedx_snapshot_build_total", %{operation: event_operation(rest)}}

  defp metric_for_event("artifact." <> rest),
    do: {"treedx_artifact_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("mirror.sync" <> _),
    do: {"treedx_mirror_sync_total", %{operation: "sync"}}

  defp metric_for_event("federated." <> rest),
    do: {"treedx_federated_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event("storage." <> rest),
    do: {"treedx_storage_operations_total", %{operation: event_operation(rest)}}

  defp metric_for_event(_event), do: nil

  defp maybe_observe_duration(event_type, data) do
    duration = data[:elapsedMs] || data["elapsedMs"] || data[:durationMs] || data["durationMs"]

    if is_number(duration) do
      case to_string(event_type) do
        "exec." <> _ -> observe("treedx_exec_duration_ms", duration, %{backend: "configured"})
        "graph.refreshed" -> observe("treedx_graph_refresh_duration_ms", duration)
        "repo.query_executed" -> observe("treedx_query_duration_ms", duration)
        "context.built" -> observe("treedx_context_build_duration_ms", duration)
        "storage.check" <> _ -> observe("treedx_storage_check_duration_ms", duration)
        "storage.compact" <> _ -> observe("treedx_storage_compaction_duration_ms", duration)
        "snapshot." <> _ -> observe("treedx_snapshot_duration_ms", duration)
        _ -> :ok
      end
    end
  end

  defp maybe_record_bytes(event_type, data) do
    bytes = data[:byteLength] || data["byteLength"] || data[:bytes] || data["bytes"]

    if is_number(bytes) and String.starts_with?(to_string(event_type), "snapshot.") do
      incr("treedx_snapshot_bytes_total", %{}, bytes)
    end
  end

  defp maybe_record_partial_failure(event_type, data) do
    count = data[:partialFailureCount] || data["partialFailureCount"] || 0

    if count > 0 and String.starts_with?(to_string(event_type), "federated.") do
      incr(
        "treedx_federated_partial_failures_total",
        %{operation: event_operation(event_type)},
        count
      )
    end
  end

  defp safe_status(attrs), do: to_string(attrs[:status] || attrs["status"] || "ok")
  defp event_operation(event), do: event |> to_string() |> String.split(".") |> List.last()

  defp materialize do
    %{
      counters:
        table_entries(@counter_table, fn {{name, labels}, value} ->
          %{name: name, labels: labels, value: value}
        end),
      histograms:
        table_entries(@histogram_table, fn histogram ->
          [key, sum, count | bucket_counts] = Tuple.to_list(histogram)
          {name, labels} = key

          %{
            name: name,
            labels: labels,
            buckets:
              Enum.zip_with(@buckets, bucket_counts, fn bucket, bucket_count ->
                %{
                  le: if(bucket == :infinity, do: "+Inf", else: bucket),
                  value: bucket_count
                }
              end),
            sum: unscale(sum),
            count: count
          }
        end),
      gauges:
        table_entries(@gauge_table, fn {{name, labels}, value} ->
          %{name: name, labels: labels, value: value}
        end)
    }
  end

  defp table_entries(table, mapper) do
    table
    |> :ets.tab2list()
    |> Enum.map(mapper)
    |> Enum.sort_by(&{&1.name, inspect(&1.labels)})
  end

  defp empty_histogram(key) do
    List.to_tuple([key, 0, 0 | List.duplicate(0, length(@buckets))])
  end

  defp histogram_updates(value) do
    bucket_updates =
      @buckets
      |> Enum.with_index(4)
      |> Enum.flat_map(fn {bucket, position} ->
        if bucket == :infinity or value <= bucket, do: [{position, 1}], else: []
      end)

    [{2, round(value * @scale)}, {3, 1} | bucket_updates]
  end

  defp tables, do: [@counter_table, @histogram_table, @gauge_table]
  defp table_exists?(table), do: :ets.whereis(table) != :undefined

  defp unscale(value) when rem(value, @scale) == 0, do: div(value, @scale)
  defp unscale(value), do: value / @scale

  defp empty_snapshot, do: %{counters: [], histograms: [], gauges: []}

  defp render_prometheus(snapshot) do
    [
      Enum.map(snapshot.counters, fn entry ->
        [
          "# HELP #{entry.name} TreeDX counter.\n",
          "# TYPE #{entry.name} counter\n",
          "#{entry.name}#{labels(entry.labels)} #{entry.value}\n"
        ]
      end),
      Enum.map(snapshot.gauges, fn entry ->
        [
          "# HELP #{entry.name} TreeDX gauge.\n",
          "# TYPE #{entry.name} gauge\n",
          "#{entry.name}#{labels(entry.labels)} #{entry.value}\n"
        ]
      end),
      Enum.map(snapshot.histograms, fn entry ->
        base = [
          "# HELP #{entry.name} TreeDX histogram.\n",
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
