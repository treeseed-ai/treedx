defmodule TreeDx.Observability.MetricsTest do
  use ExUnit.Case, async: false

  alias TreeDx.Observability.Metrics

  setup do
    Metrics.reset!()
    :ok
  end

  test "records counters, histograms, gauges, and renders prometheus text" do
    Metrics.incr("treedx_http_requests_total", %{
      method: "GET",
      route: "/api/v1/health",
      status_class: "2xx"
    })

    Metrics.observe("treedx_http_request_duration_ms", 12, %{
      method: "GET",
      route: "/api/v1/health"
    })

    Metrics.put_gauge("treedx_workspace_active_count", 2)

    snapshot = Metrics.snapshot()
    assert [%{name: "treedx_http_requests_total", value: 1}] = snapshot.counters
    assert [%{count: 1, sum: 12, buckets: buckets}] = snapshot.histograms
    assert Enum.any?(buckets, &(&1.le == 25 and &1.value == 1))

    assert Enum.any?(
             snapshot.gauges,
             &match?(%{name: "treedx_workspace_active_count", value: 2}, &1)
           )

    text = Metrics.prometheus()
    assert text =~ "# TYPE treedx_http_requests_total counter"
    assert text =~ "route=\"/api/v1/health\""
  end

  test "scrubs labels before storing metrics" do
    Metrics.incr("treedx_http_errors_total", %{
      method: "GET",
      route: "/tmp/treedx-secret",
      actorId: "actor_1",
      error_code: "permission_denied"
    })

    counter =
      Enum.find(Metrics.snapshot().counters, &(&1.name == "treedx_http_errors_total"))

    assert counter
    assert counter.value == 1
    refute Map.has_key?(counter.labels, "actor_id")
    refute Map.has_key?(counter.labels, "code")
    assert counter.labels["route"] == "redacted"
    assert counter.labels["error_code"] == "permission_denied"
  end

  test "records domain metrics from audit event boundaries" do
    for {event, metric} <- [
          {"repo.registered", "treedx_repo_operations_total"},
          {"git.push.completed", "treedx_git_remote_operations_total"},
          {"workspace.created", "treedx_workspace_operations_total"},
          {"exec.completed", "treedx_exec_runs_total"},
          {"graph.refreshed", "treedx_graph_refresh_total"},
          {"search.index_refreshed", "treedx_search_index_operations_total"},
          {"snapshot.built", "treedx_snapshot_build_total"},
          {"artifact.exported", "treedx_artifact_operations_total"},
          {"mirror.sync.completed", "treedx_mirror_sync_total"},
          {"federated.search.completed", "treedx_federated_operations_total"},
          {"storage.backup_created", "treedx_storage_operations_total"}
        ] do
      Metrics.record_audit_event(event, %{status: "ok", data: %{elapsedMs: 7, byteLength: 12}})
      assert Enum.any?(Metrics.snapshot().counters, &(&1.name == metric))
    end
  end
end
