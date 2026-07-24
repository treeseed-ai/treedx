defmodule TreeDxProfiler.ScenarioReportMetrics do
  @moduledoc false

  def operation_mix_report(opts) do
    %{
      "profilePurpose" => opts.profile_purpose,
      "performanceWorkload" => opts.performance_workload,
      "heavyOperationRate" => opts.heavy_operation_rate,
      "repoGrowthRate" => opts.repo_growth_rate,
      "snapshotRate" => opts.snapshot_rate,
      "graphRefreshRate" => opts.graph_refresh_rate,
      "importRate" => opts.import_rate,
      "rateLimited" => %{}
    }
  end

  def resource_tuning_report(state) do
    cpu_budget = System.get_env("TREEDX_RUNTIME_CPU_BUDGET")
    memory_budget_mb = System.get_env("TREEDX_RUNTIME_MEMORY_BUDGET_MB")
    cache_fraction = System.get_env("TREEDX_CACHE_MEMORY_FRACTION") || "0.25"
    metrics = state[:metrics_after] || %{}

    memory_budget_mb =
      memory_budget_mb ||
        case metric_gauge(metrics, "treedx_runtime_memory_budget_bytes") do
          bytes when is_number(bytes) and bytes > 0 ->
            Integer.to_string(div(round(bytes), 1_048_576))

          _ ->
            nil
        end

    %{
      "cpuBudget" =>
        parse_int_or_nil(cpu_budget) || metric_gauge(metrics, "treedx_runtime_cpu_budget"),
      "memoryBudgetMb" => parse_int_or_nil(memory_budget_mb),
      "cacheMemoryFraction" => parse_float_or_nil(cache_fraction),
      "cacheBudgetMb" => cache_budget_mb(memory_budget_mb, cache_fraction),
      "cachePolicy" => if(memory_budget_mb in [nil, ""], do: "entry_count", else: "memory_budget")
    }
  end

  def server_runtime_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["runtime"]) ||
      %{
        "beamMemoryBytes" => %{
          "total" => metric_gauge(metrics, "treedx_runtime_beam_memory_bytes"),
          "ets" => metric_gauge(metrics, "treedx_runtime_ets_memory_bytes"),
          "binary" => metric_gauge(metrics, "treedx_runtime_binary_memory_bytes"),
          "processes" => metric_gauge(metrics, "treedx_runtime_process_memory_bytes")
        },
        "memoryBudgetBytes" => metric_gauge(metrics, "treedx_runtime_memory_budget_bytes"),
        "cacheBudgetBytes" => metric_gauge(metrics, "treedx_runtime_cache_budget_bytes"),
        "cpuBudget" => metric_gauge(metrics, "treedx_runtime_cpu_budget")
      }
      |> reject_nil_deep()
  end

  def cache_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["cache"]) ||
      metrics
      |> metric_entries("gauges", "treedx_cache_entries")
      |> Enum.reduce(%{}, fn entry, acc ->
        cache = cache_report_key(label(entry, "cache"))

        Map.put(acc, cache, %{
          "entries" => metric_value(entry),
          "approxBytes" => cache_metric(metrics, "treedx_cache_approx_bytes", cache),
          "hits" => cache_counter(metrics, "treedx_cache_hits_total", cache),
          "misses" => cache_counter(metrics, "treedx_cache_misses_total", cache),
          "evictions" => cache_counter(metrics, "treedx_cache_evictions_total", cache)
        })
      end)
  end

  def worker_pool_report(state) do
    metrics = state[:metrics_after] || %{}

    get_in(metrics, ["workerPools"]) ||
      metrics
      |> metric_entries("gauges", "treedx_pool_size")
      |> Enum.reduce(%{}, fn entry, acc ->
        pool = pool_report_key(label(entry, "pool"))

        Map.put(acc, pool, %{
          "size" => metric_value(entry),
          "active" => pool_gauge(metrics, "treedx_pool_active", pool),
          "activeMax" => pool_gauge(metrics, "treedx_pool_active_max", pool),
          "queueDepth" => pool_gauge(metrics, "treedx_pool_queue_depth", pool),
          "queueDepthMax" => pool_gauge(metrics, "treedx_pool_queue_depth_max", pool),
          "queueMax" => pool_gauge(metrics, "treedx_pool_queue_max", pool),
          "pressure" => pressure_name(pool_gauge(metrics, "treedx_pool_pressure", pool)),
          "rejections" => pool_counter(metrics, "treedx_pool_rejections_total", pool),
          "queueTimeouts" => pool_counter(metrics, "treedx_pool_queue_timeouts_total", pool),
          "executionTimeouts" =>
            pool_counter(metrics, "treedx_pool_execution_timeouts_total", pool),
          "waitMs" => histogram_summary(metrics, "treedx_pool_wait_ms", pool),
          "executionMs" => histogram_summary(metrics, "treedx_pool_execution_ms", pool)
        })
      end)
  end

  defp metric_gauge(metrics, name), do: metric_value(find_metric(metrics, "gauges", name, %{}))

  defp pool_gauge(metrics, name, pool),
    do: metric_value(find_metric(metrics, "gauges", name, %{"pool" => pool_metric_key(pool)}))

  defp cache_metric(metrics, name, cache),
    do: metric_value(find_metric(metrics, "gauges", name, %{"cache" => cache_metric_key(cache)}))

  defp cache_counter(metrics, name, cache) do
    metrics
    |> metric_entries("counters", name)
    |> Enum.filter(&(label(&1, "cache") == cache_metric_key(cache)))
    |> Enum.map(&metric_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp pool_counter(metrics, name, pool) do
    metrics
    |> metric_entries("counters", name)
    |> Enum.filter(&(label(&1, "pool") == pool_metric_key(pool)))
    |> Enum.map(&metric_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp histogram_summary(metrics, name, pool) do
    case find_metric(metrics, "histograms", name, %{"pool" => pool_metric_key(pool)}) do
      nil ->
        %{}

      entry ->
        count = metric_field(entry, "count") || 0
        sum = metric_field(entry, "sum") || 0

        %{
          "count" => count,
          "mean" => if(count > 0, do: Float.round(sum / count, 3), else: nil)
        }
        |> reject_nil_deep()
    end
  end

  defp find_metric(metrics, kind, name, labels) do
    metrics
    |> metric_entries(kind, name)
    |> Enum.find(fn entry ->
      Enum.all?(labels, fn {key, value} -> label(entry, key) == value end)
    end)
  end

  defp metric_entries(metrics, kind, name) do
    metrics
    |> Map.get(kind, Map.get(metrics, String.to_atom(kind), []))
    |> Enum.filter(&(metric_field(&1, "name") == name))
  end

  defp metric_value(nil), do: nil
  defp metric_value(entry), do: metric_field(entry, "value")

  defp metric_field(entry, key), do: Map.get(entry, key) || Map.get(entry, String.to_atom(key))

  defp label(entry, key) do
    labels = metric_field(entry, "labels") || %{}
    Map.get(labels, key) || Map.get(labels, String.to_atom(key))
  end

  defp pool_report_key(pool), do: pool |> to_string() |> Macro.camelize() |> uncapitalize()
  defp pool_metric_key(pool), do: pool |> to_string() |> Macro.underscore()
  def cache_report_key(cache), do: cache |> to_string() |> Macro.camelize() |> uncapitalize()
  defp cache_metric_key(cache), do: cache |> to_string() |> Macro.underscore()

  defp uncapitalize(<<first::binary-size(1), rest::binary>>),
    do: String.downcase(first) <> rest

  defp uncapitalize(other), do: other

  defp pressure_name(0), do: "low"
  defp pressure_name(1), do: "moderate"
  defp pressure_name(2), do: "high"
  defp pressure_name(3), do: "saturated"
  defp pressure_name(value), do: value

  defp reject_nil_deep(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        nested = reject_nil_deep(value)
        if nested == %{}, do: acc, else: Map.put(acc, key, nested)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(value) do
    case Integer.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp parse_float_or_nil(nil), do: nil
  defp parse_float_or_nil(""), do: nil

  defp parse_float_or_nil(value) do
    case Float.parse(value) do
      {number, _} -> number
      _ -> nil
    end
  end

  defp cache_budget_mb(nil, _fraction), do: nil
  defp cache_budget_mb("", _fraction), do: nil

  defp cache_budget_mb(memory_budget_mb, fraction) do
    with mb when is_integer(mb) <- parse_int_or_nil(memory_budget_mb),
         frac when is_float(frac) <- parse_float_or_nil(fraction) do
      Float.round(mb * frac, 1)
    else
      _ -> nil
    end
  end
end
