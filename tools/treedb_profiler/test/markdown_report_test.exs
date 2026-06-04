defmodule TreeDbProfiler.MarkdownReportTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.MarkdownReport

  test "renders human-readable operation statistics" do
    markdown =
      MarkdownReport.render(%{
        "summary" => %{
          "totalCalls" => 10,
          "totalErrors" => 0,
          "successRate" => 1.0,
          "errorRate" => 0.0,
          "throughputPerSecond" => 5.0,
          "slowestOperations" => [%{"operationId" => "readRepositoryFile", "p95Ms" => 12.0}]
        },
        "workload" => %{
          "loadMode" => "portfolio",
          "fixture" => "small-docs",
          "size" => "small",
          "scenario" => "all",
          "durationMs" => 60_000,
          "concurrency" => 10,
          "includeRequests" => false
        },
        "portfolio" => %{"initialRepos" => 1, "finalRepos" => 3, "createdRepos" => 3},
        "coverage" => %{
          "openapiOperations" => 99,
          "matrixOperations" => 99,
          "exercised" => 99,
          "unaccounted" => 0
        },
        "categories" => [
          %{
            "category" => "repository_read",
            "calls" => 10,
            "successRate" => 100.0,
            "errors" => 0,
            "p95Max" => 12.0
          }
        ],
        "operations" => [
          %{
            "operationId" => "readRepositoryFile",
            "method" => "POST",
            "category" => "repository_read",
            "operationType" => "read",
            "calls" => 10,
            "successRate" => 100.0,
            "errors" => 0,
            "latencyMs" => %{
              "min" => 1.0,
              "mean" => 5.0,
              "stdev" => 1.0,
              "p50" => 5.0,
              "p95" => 12.0,
              "p99" => 12.0,
              "max" => 12.0
            }
          }
        ],
        "errors" => %{"total" => 0, "byOperation" => %{}},
        "assertions" => %{"passed" => 10, "failed" => 0},
        "requestSamples" => %{"failures" => [], "successes" => %{}}
      })

    assert markdown =~ "# TreeDB Performance Profile"
    assert markdown =~ "Portfolio Growth"
    assert markdown =~ "readRepositoryFile"
    assert markdown =~ "Operation Performance"
    assert markdown =~ "Success rate: 100.0%"
    assert markdown =~ "Error rate: 0.0%"
  end
end
