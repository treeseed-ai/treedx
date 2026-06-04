defmodule TreeDbProfiler.StatsTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.Stats

  test "aggregates latency and status by operation" do
    samples =
      for duration <- [1.0, 5.0, 10.0] do
        %{
          operation_id: "op",
          method: "GET",
          path_template: "/x",
          category: "test",
          started_at: "2026-06-03T12:00:00Z",
          duration_ms: duration,
          status: 200,
          ok: true,
          error_code: nil,
          request_bytes: 10,
          response_bytes: 20,
          assertion: :passed
        }
      end

    assert [op] = Stats.aggregate(samples)
    assert op["calls"] == 3
    assert op["status"] == %{"200" => 3}
    assert op["latencyMs"]["p95"] == 10.0
    assert op["latencyMs"]["stdev"] > 0
    assert op["successRate"] == 100.0
    assert op["bytes"]["requestAvg"] == 10.0
  end

  test "summary rates use the same percent scale as operation aggregates" do
    samples = [
      %{
        operation_id: "ok",
        method: "GET",
        path_template: "/ok",
        category: "test",
        started_at: "2026-06-03T12:00:00Z",
        duration_ms: 1.0,
        status: 200,
        ok: true,
        error_code: nil,
        request_bytes: 0,
        response_bytes: 0,
        assertion: :passed
      },
      %{
        operation_id: "fail",
        method: "GET",
        path_template: "/fail",
        category: "test",
        started_at: "2026-06-03T12:00:01Z",
        duration_ms: 1.0,
        status: 500,
        ok: false,
        error_code: "server_error",
        request_bytes: 0,
        response_bytes: 0,
        assertion: :failed
      }
    ]

    summary = Stats.summary(samples, Stats.aggregate(samples))

    assert summary["successRate"] == 50.0
    assert summary["errorRate"] == 50.0
  end
end
