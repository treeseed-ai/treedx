defmodule TreeDxProfiler.StatsTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.Stats

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

  test "throughput breakdown separates primary and validation probe traffic" do
    primary = sample("readRepositoryFile", :primary, "2026-06-03T12:00:00Z")

    probe =
      sample("readRepositoryFile.validationProbe", :validation_probe, "2026-06-03T12:00:01Z")

    report =
      Stats.throughput_breakdown([primary], [primary, probe], %{
        target_primary_rps: 1.0,
        validation_probe_mode: "sampled",
        probe_sampling_rate: 0.1
      })

    assert report["primary"]["calls"] == 1
    assert report["validationProbes"]["calls"] == 1
    assert report["totalHttp"]["calls"] == 2
    assert report["target"]["primaryRpsMet"] == true
  end

  defp sample(operation_id, kind, started_at) do
    %{
      operation_id: operation_id,
      method: "GET",
      path_template: "/x",
      category: "test",
      started_at: started_at,
      duration_ms: 1.0,
      status: 200,
      ok: true,
      error_code: nil,
      request_bytes: 0,
      response_bytes: 0,
      assertion: :passed,
      sample_kind: kind,
      counts_toward_total_http_rps: true,
      counts_toward_primary_rps: kind == :primary
    }
  end
end
