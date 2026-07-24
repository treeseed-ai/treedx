defmodule TreeDxProfiler.Stats do
  @moduledoc false

  def aggregate(samples) do
    samples
    |> Enum.group_by(& &1.operation_id)
    |> Enum.map(fn {operation_id, operation_samples} ->
      first = hd(operation_samples)
      durations = Enum.map(operation_samples, & &1.duration_ms)
      statuses = count_by(operation_samples, &Integer.to_string(&1.status || 0))
      status_classes = count_by(operation_samples, &status_class(&1.status))
      races = Enum.filter(operation_samples, &(&1.assertion == :race_interference))

      errors =
        Enum.filter(operation_samples, &(&1.ok != true and &1.assertion != :race_interference))

      assertion_failures = Enum.filter(operation_samples, &(&1.assertion == :failed))
      success = length(operation_samples) - length(errors) - length(races)
      calls = length(operation_samples)

      %{
        "operationId" => operation_id,
        "method" => first.method,
        "pathTemplate" => first.path_template,
        "category" => first.category,
        "operationType" => operation_type(first),
        "calls" => calls,
        "success" => success,
        "errors" => length(errors),
        "raceInterference" => length(races),
        "successRate" => rate(success, calls),
        "errorRate" => rate(length(errors), calls),
        "status" => statuses,
        "statusClass" => status_classes,
        "errorCodes" => count_by(errors, &(&1.error_code || "unknown")),
        "latencyMs" => latency(durations),
        "bytes" => %{
          "requestMin" => min_number(Enum.map(operation_samples, & &1.request_bytes)),
          "requestAvg" => avg(Enum.map(operation_samples, & &1.request_bytes)),
          "requestMax" => max_number(Enum.map(operation_samples, & &1.request_bytes)),
          "responseMin" => min_number(Enum.map(operation_samples, & &1.response_bytes)),
          "responseAvg" => avg(Enum.map(operation_samples, & &1.response_bytes)),
          "responseMax" => max_number(Enum.map(operation_samples, & &1.response_bytes))
        },
        "firstSeen" =>
          operation_samples
          |> Enum.map(&Map.get(&1, :started_at))
          |> Enum.reject(&is_nil/1)
          |> min_string(),
        "lastSeen" =>
          operation_samples
          |> Enum.map(&Map.get(&1, :started_at))
          |> Enum.reject(&is_nil/1)
          |> max_string(),
        "assertions" => %{
          "passed" => calls - length(assertion_failures),
          "failed" => length(assertion_failures),
          "raceInterference" => length(races)
        }
      }
    end)
    |> Enum.sort_by(& &1["operationId"])
  end

  def summary(samples, operations) do
    total = length(samples)
    errors = Enum.count(samples, &(&1.ok != true and &1.assertion != :race_interference))
    races = Enum.count(samples, &(&1.assertion == :race_interference))
    assertion_failures = Enum.count(samples, &(&1.assertion == :failed))

    %{
      "totalCalls" => total,
      "totalErrors" => errors,
      "assertionFailures" => assertion_failures,
      "raceInterference" => races,
      "errorRate" => rate(errors, total),
      "successRate" => rate(total - errors - races, total),
      "correctnessPass" => assertion_failures == 0,
      "throughputPerSecond" => throughput(samples),
      "throughputKind" => "primary",
      "slowestOperations" =>
        operations
        |> Enum.sort_by(&get_in(&1, ["latencyMs", "p95"]), :desc)
        |> Enum.take(10)
        |> Enum.map(
          &%{"operationId" => &1["operationId"], "p95Ms" => get_in(&1, ["latencyMs", "p95"])}
        ),
      "highestErrorOperations" =>
        operations
        |> Enum.filter(&(&1["errors"] > 0))
        |> Enum.sort_by(& &1["errors"], :desc)
        |> Enum.take(10)
        |> Enum.map(&%{"operationId" => &1["operationId"], "errors" => &1["errors"]})
    }
  end

  def throughput_breakdown(primary_samples, http_samples, opts) do
    validation_probe_samples = samples_of_kind(http_samples, :validation_probe)
    reconciliation_samples = samples_of_kind(http_samples, :reconciliation)

    auxiliary_samples =
      Enum.reject(http_samples, fn sample ->
        Map.get(sample, :sample_kind, :primary) in [:primary, :validation_probe, :reconciliation]
      end)

    primary = throughput_group(primary_samples)
    validation = throughput_group(validation_probe_samples)
    reconciliation = throughput_group(reconciliation_samples)
    auxiliary = throughput_group(auxiliary_samples)
    total_http = throughput_group(http_samples)
    target = target_report(primary["requestsPerSecond"], opts)

    %{
      "targetPrimaryRps" => opts.target_primary_rps,
      "primary" =>
        Map.merge(primary, %{
          "successRate" => success_rate(primary_samples),
          "errorRate" => error_rate(primary_samples),
          "measuredDurationMs" => duration_ms(primary_samples)
        }),
      "validationProbes" =>
        Map.merge(validation, %{
          "failed" => Enum.count(validation_probe_samples, &(&1.ok != true)),
          "sampled" => opts.validation_probe_mode == "sampled",
          "samplingRate" => opts.probe_sampling_rate
        }),
      "reconciliation" =>
        Map.merge(reconciliation, %{
          "failed" => Enum.count(reconciliation_samples, &(&1.ok != true))
        }),
      "auxiliary" => auxiliary,
      "totalHttp" => total_http,
      "target" => target
    }
  end

  def category_aggregates(operations) do
    operations
    |> Enum.group_by(& &1["category"])
    |> Enum.map(fn {category, ops} -> aggregate_operation_group(category, ops) end)
    |> Enum.sort_by(& &1["category"])
  end

  def operation_type_aggregates(operations) do
    operations
    |> Enum.group_by(& &1["operationType"])
    |> Enum.map(fn {type, ops} -> aggregate_operation_group(type, ops, "operationType") end)
    |> Enum.sort_by(& &1["operationType"])
  end

  def saturation_report(samples) do
    busy = Enum.filter(samples, &(&1.error_code == "server_busy"))

    %{
      "serverBusy" => %{
        "total" => length(busy),
        "byOperation" => count_by(busy, & &1.operation_id),
        "byPool" => count_by(busy, &busy_detail(&1, "pool")),
        "byReason" => count_by(busy, &busy_detail(&1, "reason")),
        "samples" =>
          busy
          |> Enum.take(25)
          |> Enum.map(fn sample ->
            %{
              "operationId" => sample.operation_id,
              "status" => sample.status,
              "pool" => busy_detail(sample, "pool"),
              "reason" => busy_detail(sample, "reason"),
              "elapsedMs" => sample.duration_ms
            }
          end)
      }
    }
  end

  def latency([]), do: empty_latency()

  def latency(values) do
    sorted = Enum.sort(values)

    %{
      "min" => Float.round(List.first(sorted), 3),
      "mean" => Float.round(avg(sorted), 3),
      "stdev" => Float.round(stdev(sorted), 3),
      "p50" => percentile(sorted, 50),
      "p75" => percentile(sorted, 75),
      "p90" => percentile(sorted, 90),
      "p95" => percentile(sorted, 95),
      "p99" => percentile(sorted, 99),
      "max" => Float.round(List.last(sorted), 3)
    }
  end

  def percentile([], _), do: 0.0

  def percentile(sorted, pct) do
    index =
      (pct / 100 * (length(sorted) - 1))
      |> Float.ceil()
      |> trunc()

    sorted
    |> Enum.at(index)
    |> Float.round(3)
  end

  defp count_by(values, fun) do
    values
    |> Enum.reduce(%{}, fn value, acc ->
      key = fun.(value)
      Map.update(acc, key, 1, &(&1 + 1))
    end)
    |> Enum.sort()
    |> Map.new()
  end

  defp avg([]), do: 0.0
  defp avg(values), do: Enum.sum(values) / length(values)

  defp empty_latency do
    %{
      "min" => 0.0,
      "mean" => 0.0,
      "stdev" => 0.0,
      "p50" => 0.0,
      "p75" => 0.0,
      "p90" => 0.0,
      "p95" => 0.0,
      "p99" => 0.0,
      "max" => 0.0
    }
  end

  defp aggregate_operation_group(name, operations, key \\ "category") do
    calls = Enum.sum(Enum.map(operations, & &1["calls"]))
    errors = Enum.sum(Enum.map(operations, & &1["errors"]))
    races = Enum.sum(Enum.map(operations, &(&1["raceInterference"] || 0)))

    %{
      key => name,
      "calls" => calls,
      "success" => calls - errors,
      "errors" => errors,
      "raceInterference" => races,
      "successRate" => rate(calls - errors - races, calls),
      "errorRate" => rate(errors, calls),
      "p95Max" => operations |> Enum.map(&get_in(&1, ["latencyMs", "p95"])) |> max_number()
    }
  end

  defp stdev([]), do: 0.0
  defp stdev([_]), do: 0.0

  defp stdev(values) do
    mean = avg(values)

    values
    |> Enum.map(&:math.pow(&1 - mean, 2))
    |> avg()
    |> :math.sqrt()
  end

  defp min_number([]), do: 0
  defp min_number(values), do: Enum.min(values)
  defp max_number([]), do: 0
  defp max_number(values), do: Enum.max(values)
  defp min_string([]), do: nil
  defp min_string(values), do: Enum.min(values)
  defp max_string([]), do: nil
  defp max_string(values), do: Enum.max(values)

  defp rate(_value, 0), do: 0.0
  defp rate(value, total), do: Float.round(value / total * 100.0, 4)

  defp status_class(nil), do: "unknown"
  defp status_class(status) when status >= 100, do: "#{div(status, 100)}xx"
  defp status_class(_), do: "unknown"

  defp operation_type(sample) do
    case sample.category do
      "repository_read" -> "read"
      "repository_query" -> "query"
      "workspace" -> "workspace"
      "graph" -> "graph"
      "context" -> "query"
      "blob" -> "blob"
      "artifact" -> "artifact"
      "snapshot" -> "artifact"
      "admin" -> "admin"
      "policy" -> "policy"
      "auth" -> "auth"
      "operations" -> "operations"
      other -> other || "unknown"
    end
  end

  defp busy_detail(sample, key) do
    details = Map.get(sample, :error_details) || %{}
    to_string(details[key] || details[String.to_atom(key)] || "unknown")
  rescue
    _ -> "unknown"
  end

  defp throughput([]), do: 0.0

  defp throughput(samples) do
    times =
      samples
      |> Enum.map(&DateTime.from_iso8601(&1.started_at))
      |> Enum.flat_map(fn
        {:ok, dt, _} -> [DateTime.to_unix(dt, :millisecond)]
        _ -> []
      end)

    case times do
      [] ->
        0.0

      _ ->
        duration_seconds = max((Enum.max(times) - Enum.min(times)) / 1000.0, 1.0)
        Float.round(length(samples) / duration_seconds, 3)
    end
  end

  defp throughput_group(samples) do
    %{
      "calls" => length(samples),
      "requestsPerSecond" => throughput(samples)
    }
  end

  defp target_report(_primary_rps, %{target_primary_rps: nil}) do
    %{
      "primaryRps" => nil,
      "primaryRpsMet" => nil,
      "primaryRpsRatio" => nil
    }
  end

  defp target_report(primary_rps, %{target_primary_rps: target}) do
    %{
      "primaryRps" => target,
      "primaryRpsMet" => primary_rps >= target,
      "primaryRpsRatio" => if(target > 0, do: Float.round(primary_rps / target, 4), else: nil)
    }
  end

  defp samples_of_kind(samples, kind) do
    Enum.filter(samples, &(Map.get(&1, :sample_kind, :primary) == kind))
  end

  defp success_rate(samples) do
    total = length(samples)
    success = Enum.count(samples, &(&1.ok == true and &1.assertion != :race_interference))
    rate(success, total)
  end

  defp error_rate(samples) do
    total = length(samples)
    errors = Enum.count(samples, &(&1.ok != true and &1.assertion != :race_interference))
    rate(errors, total)
  end

  defp duration_ms([]), do: 0

  defp duration_ms(samples) do
    times =
      samples
      |> Enum.map(&DateTime.from_iso8601(&1.started_at))
      |> Enum.flat_map(fn
        {:ok, dt, _} -> [DateTime.to_unix(dt, :millisecond)]
        _ -> []
      end)

    case times do
      [] -> 0
      _ -> Enum.max(times) - Enum.min(times)
    end
  end
end
