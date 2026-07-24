defmodule TreeDxProfiler.ReliabilityBudgetTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.ReliabilityBudget

  test "passes when report stays within budget" do
    report =
      report(%{
        "durationMs" => 60_000,
        "requestedDurationMs" => 60_000,
        "durationSatisfied" => true
      })

    assert %{"passed" => true, "violations" => []} =
             ReliabilityBudget.evaluate(report, %{reliability_budget: nil})
  end

  test "fails short measured duration" do
    report =
      report(%{
        "durationMs" => 30_000,
        "requestedDurationMs" => 60_000,
        "durationSatisfied" => false,
        "stopReason" => "duration_limit"
      })

    result = ReliabilityBudget.evaluate(report, %{reliability_budget: nil})
    refute result["passed"]
    assert Enum.any?(result["violations"], &(&1["key"] == "measured_duration"))
  end

  test "passes short iteration-limited smoke runs when minimum duration is satisfied" do
    report =
      report(%{
        "durationMs" => 250,
        "requestedDurationMs" => 60_000,
        "durationSatisfied" => true,
        "minimumMeasuredDurationMs" => 0,
        "stopReason" => "iteration_limit"
      })

    assert %{"passed" => true, "violations" => []} =
             ReliabilityBudget.evaluate(report, %{reliability_budget: nil})
  end

  test "fails permission matrix failures" do
    report =
      report(%{
        "durationMs" => 60_000,
        "requestedDurationMs" => 60_000,
        "durationSatisfied" => true
      })
      |> put_in(["permissionMatrix"], %{"failed" => 1})

    result = ReliabilityBudget.evaluate(report, %{reliability_budget: nil})
    refute result["passed"]
    assert Enum.any?(result["violations"], &(&1["key"] == "permission_matrix_failures"))
  end

  test "custom empty p99 category budget disables latency thresholds" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-budget-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    budget_path = Path.join(root, "budget.json")
    File.write!(budget_path, Jason.encode!(%{"maxP99MsByCategory" => %{}}))

    report =
      report(%{
        "durationMs" => 60_000,
        "requestedDurationMs" => 60_000,
        "durationSatisfied" => true
      })
      |> Map.put("operations", [
        %{
          "operationId" => "slowButCorrect",
          "category" => "operations",
          "latencyMs" => %{"p99" => 30_000}
        }
      ])

    assert %{"passed" => true, "violations" => []} =
             ReliabilityBudget.evaluate(report, %{reliability_budget: budget_path})
  end

  defp report(measured) do
    %{
      "summary" => %{"totalErrors" => 0, "totalCalls" => 1},
      "assertions" => %{"failed" => 0},
      "openapiValidation" => %{"failed" => 0},
      "reconciliation" => %{"drift" => %{"total" => 0}},
      "concurrency" => %{"raceInterference" => %{"unverified" => 0, "total" => 0}},
      "validationProbes" => %{"failed" => 0},
      "negativeTests" => %{"failed" => 0},
      "metamorphic" => %{"failed" => 0},
      "endpointConsistency" => %{"failed" => 0},
      "delayedConsistency" => %{"failed" => 0},
      "permissionMatrix" => %{"failed" => 0},
      "operations" => [],
      "timing" => %{"measured" => measured}
    }
  end
end
