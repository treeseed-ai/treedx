defmodule TreeDxProfiler.FailureSummaryTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.FailureSummary

  test "summarizes policy failures from the generated profile report" do
    report = %{
      "summary" => %{"totalErrors" => 2},
      "errors" => %{"byOperation" => %{"readRepositoryFile" => 2}},
      "assertions" => %{
        "failed" => 1,
        "failures" => [
          %{
            "operation_id" => "federationTopology",
            "rule" => "sync_node_b",
            "message" => "POST /api/v1/federation/catalog/sync failed with 500"
          }
        ]
      },
      "reliabilityBudget" => %{
        "passed" => false,
        "violations" => [
          %{"key" => "assertion_failures", "actual" => 1, "limit" => 0}
        ]
      },
      "throughput" => %{"primary" => %{"requestsPerSecond" => 4.5}},
      "requestSamples" => %{
        "failures" => [
          %{
            "operationId" => "readRepositoryFile",
            "status" => 500,
            "errorCode" => "internal_error",
            "assertion" => "failed"
          }
        ]
      }
    }

    lines = FailureSummary.lines(report, %{fail_below_primary_rps: 5.0})

    assert Enum.any?(lines, &(&1 =~ "total errors: 2"))
    assert Enum.any?(lines, &(&1 =~ "federationTopology sync_node_b"))
    assert Enum.any?(lines, &(&1 =~ "reliability budget failed"))
    assert Enum.any?(lines, &(&1 =~ "primary RPS below threshold"))
    assert Enum.any?(lines, &(&1 =~ "retained failure samples"))
  end

  test "returns no lines for a passing report" do
    assert FailureSummary.lines(%{
             "summary" => %{"totalErrors" => 0},
             "assertions" => %{"failed" => 0},
             "reliabilityBudget" => %{"passed" => true},
             "throughput" => %{"primary" => %{"requestsPerSecond" => 10.0}}
           }) == []
  end
end
