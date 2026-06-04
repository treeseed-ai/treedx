defmodule TreeDbProfiler.MarkdownReport do
  @moduledoc false

  def render(report) do
    [
      "# TreeDB Performance Profile",
      "",
      summary(report),
      workload(report),
      portfolio(report),
      coverage(report),
      category_table(report),
      operation_table(report),
      slowest(report),
      errors(report),
      assertions(report),
      request_samples(report)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp summary(report) do
    summary = report["summary"] || %{}

    """
    ## Summary

    - Total calls: #{summary["totalCalls"] || 0}
    - Total errors: #{summary["totalErrors"] || 0}
    - Success rate: #{format_rate(summary["successRate"] || 0.0)}%
    - Error rate: #{format_rate(summary["errorRate"] || 0.0)}%
    - Throughput: #{summary["throughputPerSecond"] || 0.0} requests/second
    """
  end

  defp format_rate(rate) when is_number(rate) and rate <= 1.0, do: Float.round(rate * 100, 4)
  defp format_rate(rate) when is_number(rate), do: Float.round(rate, 4)
  defp format_rate(_rate), do: 0.0

  defp workload(report) do
    workload = report["workload"] || %{}

    """
    ## Workload

    - Load mode: #{workload["loadMode"]}
    - Fixture: #{workload["fixture"]}
    - Size: #{workload["size"]}
    - Scenario: #{workload["scenario"]}
    - Duration: #{workload["durationMs"] || "iteration-limited"} ms
    - Concurrency: #{workload["concurrency"]}
    - Request details included: #{workload["includeRequests"]}
    """
  end

  defp portfolio(report) do
    case report["portfolio"] || %{} do
      map when map == %{} ->
        ""

      portfolio ->
        """
        ## Portfolio Growth

        - Initial repositories: #{portfolio["initialRepos"] || 0}
        - Final repositories: #{portfolio["finalRepos"] || 0}
        - Created repositories: #{portfolio["createdRepos"] || 0}
        - Deleted repositories: #{portfolio["deletedRepos"] || 0}
        - Active workspaces: #{portfolio["activeWorkspaces"] || 0}
        - Closed workspaces: #{portfolio["closedWorkspaces"] || 0}
        - Files generated: #{portfolio["filesGenerated"] || 0}
        - Files deleted: #{portfolio["filesDeleted"] || 0}
        - Blobs generated: #{portfolio["blobsGenerated"] || 0}
        - Snapshots built: #{portfolio["snapshotsBuilt"] || 0}
        - Artifacts exported: #{portfolio["artifactsExported"] || 0}
        - Commits created: #{portfolio["commitsCreated"] || 0}
        """
    end
  end

  defp coverage(report) do
    coverage = report["coverage"] || %{}

    """
    ## Endpoint Coverage

    - OpenAPI operations: #{coverage["openapiOperations"] || 0}
    - Matrix operations: #{coverage["matrixOperations"] || 0}
    - Exercised: #{coverage["exercised"] || 0}
    - Unaccounted: #{coverage["unaccounted"] || 0}
    """
  end

  defp category_table(report) do
    rows =
      report
      |> Map.get("categories", [])
      |> Enum.map(fn category ->
        "| #{category["category"]} | #{category["calls"]} | #{category["successRate"]}% | #{category["errors"]} | #{category["p95Max"]} |"
      end)

    """
    ## Category Performance

    | Category | Calls | Success Rate | Errors | Max p95 ms |
    |---|---:|---:|---:|---:|
    #{Enum.join(rows, "\n")}
    """
  end

  defp operation_table(report) do
    rows =
      report
      |> Map.get("operations", [])
      |> Enum.map(fn op ->
        latency = op["latencyMs"] || %{}

        "| #{op["operationId"]} | #{op["method"]} | #{op["category"]} | #{op["operationType"]} | #{op["calls"]} | #{op["successRate"]}% | #{latency["min"]} | #{latency["mean"]} | #{latency["stdev"]} | #{latency["p50"]} | #{latency["p95"]} | #{latency["p99"]} | #{latency["max"]} | #{op["errors"]} |"
      end)

    """
    ## Operation Performance

    | Operation | Method | Category | Type | Calls | Success | Min | Mean | Stdev | p50 | p95 | p99 | Max | Errors |
    |---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
    #{Enum.join(rows, "\n")}
    """
  end

  defp slowest(report) do
    rows =
      report
      |> get_in(["summary", "slowestOperations"])
      |> List.wrap()
      |> Enum.map(&"- #{&1["operationId"]}: p95 #{&1["p95Ms"]} ms")
      |> Enum.join("\n")

    "## Slowest Operations\n\n#{rows}\n"
  end

  defp errors(report) do
    errors = report["errors"] || %{}

    """
    ## Errors

    - Total: #{errors["total"] || 0}
    - By operation: `#{inspect(errors["byOperation"] || %{})}`
    """
  end

  defp assertions(report) do
    assertions = report["assertions"] || %{}

    """
    ## Assertions

    - Passed: #{assertions["passed"] || 0}
    - Failed: #{assertions["failed"] || 0}
    """
  end

  defp request_samples(report) do
    samples = report["requestSamples"] || %{}
    failures = samples["failures"] || []
    successes = samples["successes"] || %{}

    """
    ## Retained Request Samples

    - Failure samples: #{length(failures)}
    - Success sample groups: #{map_size(successes)}
    """
  end
end
