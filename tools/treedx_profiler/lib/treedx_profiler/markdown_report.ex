defmodule TreeDxProfiler.MarkdownReport do
  @moduledoc false

  def render(report) do
    [
      "# TreeDX Performance Profile",
      "",
      summary(report),
      timing(report),
      throughput(report),
      reliability_budget(report),
      workload(report),
      portfolio(report),
      coverage(report),
      model_state(report),
      reconciliation(report),
      operation_chains(report),
      category_table(report),
      operation_table(report),
      semantic_validation(report),
      openapi_validation(report),
      negative_tests(report),
      metamorphic(report),
      delayed_consistency(report),
      endpoint_consistency(report),
      race_interference(report),
      replay(report),
      leak_detection(report),
      permission_matrix(report),
      restart_and_faults(report),
      saturation(report),
      federation_load_balancing(report),
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
    throughput = report["throughput"] || %{}
    primary = throughput["primary"] || %{}
    total_http = throughput["totalHttp"] || %{}
    probes = throughput["validationProbes"] || %{}
    target = throughput["target"] || %{}

    """
    ## Summary

    - Primary calls: #{summary["totalCalls"] || 0}
    - Primary throughput: #{primary["requestsPerSecond"] || summary["throughputPerSecond"] || 0.0} requests/second
    - Total HTTP calls: #{total_http["calls"] || summary["totalCalls"] || 0}
    - Total HTTP throughput: #{total_http["requestsPerSecond"] || 0.0} requests/second
    - Validation probe throughput: #{probes["requestsPerSecond"] || 0.0} requests/second
    - Target primary RPS: #{target["primaryRps"] || "not set"}
    - Target primary RPS met: #{target["primaryRpsMet"]}
    - Total errors: #{summary["totalErrors"] || 0}
    - Assertion failures: #{summary["assertionFailures"] || 0}
    - Race interference: #{summary["raceInterference"] || 0}
    - Correctness pass: #{summary["correctnessPass"]}
    - Success rate: #{format_rate(summary["successRate"] || 0.0)}%
    - Error rate: #{format_rate(summary["errorRate"] || 0.0)}%
    """
  end

  defp format_rate(rate) when is_number(rate) and rate <= 1.0, do: Float.round(rate * 100, 4)
  defp format_rate(rate) when is_number(rate), do: Float.round(rate, 4)
  defp format_rate(_rate), do: 0.0

  defp timing(report) do
    measured = get_in(report, ["timing", "measured"]) || %{}
    profile = get_in(report, ["timing", "profile"]) || %{}
    setup = get_in(report, ["timing", "setup"]) || %{}
    cleanup = get_in(report, ["timing", "cleanup"]) || %{}

    """
    ## Timing

    - Profile started: #{profile["startedAt"]}
    - Profile ended: #{profile["endedAt"]}
    - Profile duration: #{profile["durationMs"] || 0} ms
    - Setup duration: #{setup["durationMs"] || 0} ms
    - Measured load started: #{measured["startedAt"]}
    - Measured load ended: #{measured["endedAt"]}
    - Requested measured duration: #{measured["requestedDurationMs"] || "none"} ms
    - Actual measured duration: #{measured["durationMs"] || 0} ms
    - Measured duration satisfied: #{measured["durationSatisfied"]}
    - Stop reason: #{measured["stopReason"]}
    - Cleanup duration: #{cleanup["durationMs"] || 0} ms
    """
  end

  defp throughput(report) do
    throughput = report["throughput"] || %{}
    primary = throughput["primary"] || %{}
    probes = throughput["validationProbes"] || %{}
    reconciliation = throughput["reconciliation"] || %{}
    auxiliary = throughput["auxiliary"] || %{}
    total = throughput["totalHttp"] || %{}
    target = throughput["target"] || %{}

    """
    ## Throughput Breakdown

    - Primary calls: #{primary["calls"] || 0}
    - Primary RPS: #{primary["requestsPerSecond"] || 0.0}
    - Validation probe calls: #{probes["calls"] || 0}
    - Validation probe RPS: #{probes["requestsPerSecond"] || 0.0}
    - Reconciliation calls: #{reconciliation["calls"] || 0}
    - Reconciliation RPS: #{reconciliation["requestsPerSecond"] || 0.0}
    - Auxiliary calls: #{auxiliary["calls"] || 0}
    - Auxiliary RPS: #{auxiliary["requestsPerSecond"] || 0.0}
    - Total HTTP calls: #{total["calls"] || 0}
    - Total HTTP RPS: #{total["requestsPerSecond"] || 0.0}
    - Target primary RPS: #{target["primaryRps"] || "not set"}
    - Target ratio: #{target["primaryRpsRatio"] || "not set"}
    """
  end

  defp reliability_budget(report) do
    budget = report["reliabilityBudget"] || %{}

    """
    ## Reliability Budget

    - Passed: #{budget["passed"]}
    - Violations: #{length(budget["violations"] || [])}
    """
  end

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

  defp model_state(report) do
    model = report["modelState"] || %{}

    """
    ## Model State Summary

    - Repositories: #{model["repos"] || 0}
    - Workspaces: #{model["workspaces"] || 0}
    - Snapshots: #{model["snapshots"] || 0}
    - Artifacts: #{model["artifacts"] || 0}
    - Graph repositories: #{model["graphRepos"] || 0}
    - Search terms: #{model["searchTerms"] || 0}
    """
  end

  defp reconciliation(report) do
    reconciliation = report["reconciliation"] || %{}

    """
    ## Reconciliation

    - Runs: #{reconciliation["totalRuns"] || 0}
    - Passed: #{reconciliation["passed"] || 0}
    - Failed: #{reconciliation["failed"] || 0}
    - Drift samples: #{get_in(reconciliation, ["drift", "total"]) || 0}
    """
  end

  defp operation_chains(report) do
    chains = report["operationChains"] || %{}

    """
    ## Operation Chains

    - Enabled: #{chains["enabled"]}
    - Total: #{chains["total"] || 0}
    - Passed: #{chains["passed"] || 0}
    - Failed: #{chains["failed"] || 0}
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

        assertions = op["assertions"] || %{}

        "| #{op["operationId"]} | #{op["method"]} | #{op["category"]} | #{op["operationType"]} | #{op["calls"]} | #{op["successRate"]}% | #{latency["min"]} | #{latency["mean"]} | #{latency["stdev"]} | #{latency["p50"]} | #{latency["p95"]} | #{latency["p99"]} | #{latency["max"]} | #{op["errors"]} | #{assertions["failed"] || 0} | #{op["raceInterference"] || 0} |"
      end)

    """
    ## Operation Performance

    | Operation | Method | Category | Type | Calls | Success | Min | Mean | Stdev | p50 | p95 | p99 | Max | Errors | Assertion Failures | Race |
    |---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
    #{Enum.join(rows, "\n")}
    """
  end

  defp semantic_validation(report) do
    validation = report["validation"] || %{}
    probes = report["validationProbes"] || %{}

    """
    ## Semantic Correctness

    - Semantic validation: #{validation["semanticValidation"]}
    - Validation probes enabled: #{validation["validationProbes"]}
    - Validation probes total: #{probes["total"] || 0}
    - Validation probes failed: #{probes["failed"] || 0}
    - Strict query hit counts: #{validation["strictQueryHitCounts"]}
    - Strict graph expectations: #{validation["strictGraphExpectations"]}
    - Strict snapshot stability: #{validation["strictSnapshotStability"]}
    """
  end

  defp openapi_validation(report) do
    validation = report["openapiValidation"] || %{}

    """
    ## OpenAPI Validation

    - Responses: #{validation["totalResponses"] || 0}
    - Passed: #{validation["passed"] || 0}
    - Failed: #{validation["failed"] || 0}
    """
  end

  defp negative_tests(report) do
    tests = report["negativeTests"] || %{}

    """
    ## Negative Tests

    - Enabled: #{tests["enabled"]}
    - Total: #{tests["total"] || 0}
    - Passed: #{tests["passed"] || 0}
    - Failed: #{tests["failed"] || 0}
    """
  end

  defp metamorphic(report) do
    checks = report["metamorphic"] || %{}

    """
    ## Metamorphic Checks

    - Enabled: #{checks["enabled"]}
    - Total: #{checks["total"] || 0}
    - Passed: #{checks["passed"] || 0}
    - Failed: #{checks["failed"] || 0}
    """
  end

  defp delayed_consistency(report) do
    checks = report["delayedConsistency"] || %{}

    """
    ## Delayed Consistency

    - Enabled: #{checks["enabled"]}
    - Scheduled: #{checks["scheduled"] || 0}
    - Completed: #{checks["completed"] || 0}
    - Failed: #{checks["failed"] || 0}
    """
  end

  defp endpoint_consistency(report) do
    checks = report["endpointConsistency"] || %{}

    """
    ## Endpoint Consistency

    - Total: #{checks["total"] || 0}
    - Passed: #{checks["passed"] || 0}
    - Failed: #{checks["failed"] || 0}
    """
  end

  defp race_interference(report) do
    race = get_in(report, ["concurrency", "raceInterference"]) || %{}

    """
    ## Concurrency And Race Interference

    - Race policy: #{get_in(report, ["concurrency", "racePolicy"])}
    - Total race interference: #{race["total"] || 0}
    - By operation: `#{inspect(race["byOperation"] || %{})}`
    - By cause: `#{inspect(race["byCause"] || %{})}`
    """
  end

  defp replay(report) do
    replay = report["replay"] || %{}

    """
    ## Replay Logs

    - Request ledger: #{replay["requestLedger"]}
    - Replay log: #{replay["replayLog"]}
    - Failure replay log: #{replay["failureReplayLog"]}
    """
  end

  defp leak_detection(report) do
    leak = report["leakDetection"] || %{}

    """
    ## Leak Detection

    - Samples: #{leak["samples"] || 0}
    - Warnings: #{length(leak["warnings"] || [])}
    - Failures: #{length(leak["failures"] || [])}
    """
  end

  defp permission_matrix(report) do
    matrix = report["permissionMatrix"] || %{}

    """
    ## Permission Matrix

    - Enabled: #{matrix["enabled"]}
    - Total: #{matrix["total"] || 0}
    - Passed: #{matrix["passed"] || 0}
    - Failed: #{matrix["failed"] || 0}
    """
  end

  defp restart_and_faults(report) do
    restart = report["restartDurability"] || %{}
    faults = report["faultInjection"] || %{}

    """
    ## Restart Durability

    - Enabled: #{restart["enabled"]}
    - Restarts: #{restart["restarts"] || 0}
    - Readiness recovered: #{restart["readinessRecovered"]}

    ## Fault Injection

    - Enabled: #{faults["enabled"]}
    - Injected: #{faults["injected"] || 0}
    - Recovered: #{faults["recovered"] || 0}
    - Failures: #{length(faults["failures"] || [])}
    """
  end

  defp saturation(report) do
    saturation = report["saturation"] || %{}
    server_busy = saturation["serverBusy"] || %{}

    """
    ## Saturation And Queues

    - Server busy responses: #{server_busy["total"] || 0}
    - By operation: `#{inspect(server_busy["byOperation"] || %{})}`
    - By pool: `#{inspect(server_busy["byPool"] || %{})}`
    - By reason: `#{inspect(server_busy["byReason"] || %{})}`
    """
  end

  defp federation_load_balancing(report) do
    balancing = report["federationLoadBalancing"] || %{}

    """
    ## Federation Load-Aware Routing

    - Enabled: #{balancing["enabled"]}
    - Read spillovers: #{balancing["readSpillovers"] || 0}
    - Failures: #{balancing["failures"] || 0}
    - By target node: `#{inspect(balancing["byTargetNode"] || %{})}`
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
    - Race interference: #{assertions["raceInterference"] || 0}
    - Unavailable: #{assertions["unavailable"] || 0}
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
