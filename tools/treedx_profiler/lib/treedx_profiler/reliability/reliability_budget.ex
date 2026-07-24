defmodule TreeDxProfiler.ReliabilityBudget do
  @moduledoc false

  @defaults %{
    "maxTotalErrors" => 0,
    "maxAssertionFailures" => 0,
    "maxOpenApiFailures" => 0,
    "maxReconciliationDrift" => 0,
    "maxUnverifiedRaces" => 0,
    "maxValidationProbeFailures" => 0,
    "maxNegativeTestFailures" => 0,
    "maxMetamorphicFailures" => 0,
    "maxEndpointConsistencyFailures" => 0,
    "maxDelayedConsistencyFailures" => 0,
    "maxPermissionMatrixFailures" => 0,
    "minMeasuredDurationRatio" => 0.99,
    "maxRaceInterferenceRate" => 5.0,
    "maxP99MsByCategory" => %{
      "operations" => 5000,
      "repository_read" => 30_000,
      "repository_query" => 30_000,
      "workspace" => 30_000,
      "graph" => 30_000,
      "snapshot" => 30_000,
      "artifact" => 30_000
    }
  }

  def load(path) do
    if path && File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> deep_merge(@defaults)
    else
      @defaults
    end
  rescue
    _ -> @defaults
  end

  def evaluate(report, opts) do
    budget = load(Map.get(opts, :reliability_budget))

    violations =
      []
      |> check_max(
        "total_errors",
        get_in(report, ["summary", "totalErrors"]),
        budget["maxTotalErrors"]
      )
      |> check_max(
        "assertion_failures",
        get_in(report, ["assertions", "failed"]),
        budget["maxAssertionFailures"]
      )
      |> check_max(
        "openapi_failures",
        get_in(report, ["openapiValidation", "failed"]),
        budget["maxOpenApiFailures"]
      )
      |> check_max(
        "reconciliation_drift",
        get_in(report, ["reconciliation", "drift", "total"]),
        budget["maxReconciliationDrift"]
      )
      |> check_max(
        "unverified_races",
        get_in(report, ["concurrency", "raceInterference", "unverified"]),
        budget["maxUnverifiedRaces"]
      )
      |> check_max(
        "validation_probe_failures",
        get_in(report, ["validationProbes", "failed"]),
        budget["maxValidationProbeFailures"]
      )
      |> check_max(
        "negative_test_failures",
        get_in(report, ["negativeTests", "failed"]),
        budget["maxNegativeTestFailures"]
      )
      |> check_max(
        "metamorphic_failures",
        get_in(report, ["metamorphic", "failed"]),
        budget["maxMetamorphicFailures"]
      )
      |> check_max(
        "endpoint_consistency_failures",
        get_in(report, ["endpointConsistency", "failed"]),
        budget["maxEndpointConsistencyFailures"]
      )
      |> check_max(
        "delayed_consistency_failures",
        get_in(report, ["delayedConsistency", "failed"]),
        budget["maxDelayedConsistencyFailures"]
      )
      |> check_max(
        "permission_matrix_failures",
        get_in(report, ["permissionMatrix", "failed"]),
        budget["maxPermissionMatrixFailures"]
      )
      |> check_duration(report, budget)
      |> check_race_rate(report, budget)
      |> check_category_p99(report, budget)

    %{
      "passed" => violations == [],
      "violations" => violations,
      "budget" => budget
    }
  end

  defp check_max(violations, _key, _value, nil), do: violations
  defp check_max(violations, _key, nil, _max), do: violations

  defp check_max(violations, key, value, max) when value > max,
    do: [%{"key" => key, "actual" => value, "limit" => max} | violations]

  defp check_max(violations, _key, _value, _max), do: violations

  defp check_duration(violations, report, budget) do
    measured = get_in(report, ["timing", "measured"]) || %{}
    requested = measured["requestedDurationMs"]
    duration = measured["durationMs"] || 0
    ratio = budget["minMeasuredDurationRatio"] || 0.99
    duration_controlled? = measured["stopReason"] in [nil, "duration_limit", "completed"]

    cond do
      is_nil(requested) ->
        violations

      measured["durationSatisfied"] == false ->
        duration_violation(violations, duration, requested, ratio)

      duration_controlled? and duration < requested * ratio ->
        duration_violation(violations, duration, requested, ratio)

      true ->
        violations
    end
  end

  defp duration_violation(violations, duration, requested, ratio),
    do: [
      %{
        "key" => "measured_duration",
        "actual" => duration,
        "limit" => requested * ratio,
        "requestedDurationMs" => requested
      }
      | violations
    ]

  defp check_race_rate(violations, report, budget) do
    total = get_in(report, ["summary", "totalCalls"]) || 0
    races = get_in(report, ["concurrency", "raceInterference", "total"]) || 0
    max_rate = budget["maxRaceInterferenceRate"] || 5.0
    rate = if total > 0, do: races / total * 100.0, else: 0.0

    if rate > max_rate,
      do: [
        %{"key" => "race_interference_rate", "actual" => rate, "limit" => max_rate} | violations
      ],
      else: violations
  end

  defp check_category_p99(violations, report, budget) do
    limits = budget["maxP99MsByCategory"] || %{}

    report
    |> Map.get("operations", [])
    |> Enum.reduce(violations, fn operation, acc ->
      category = operation["category"]
      limit = limits[category]
      p99 = get_in(operation, ["latencyMs", "p99"]) || 0

      if limit && p99 > limit do
        [
          %{
            "key" => "category_p99",
            "category" => category,
            "operationId" => operation["operationId"],
            "actual" => p99,
            "limit" => limit
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp deep_merge(map, defaults) when is_map(map) do
    Map.merge(defaults, map, fn _key, default, value ->
      cond do
        is_map(default) and is_map(value) and map_size(value) > 0 ->
          deep_merge(value, default)

        true ->
          value
      end
    end)
  end

  defp deep_merge(_map, defaults), do: defaults
end
