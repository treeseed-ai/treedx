defmodule TreeDb.Observability.MetricsTest do
  use ExUnit.Case, async: false

  alias TreeDb.Observability.Metrics

  setup do
    Metrics.reset!()
    :ok
  end

  test "records counters, histograms, gauges, and renders prometheus text" do
    Metrics.incr("treedb_http_requests_total", %{
      method: "GET",
      route: "/api/v1/health",
      status_class: "2xx"
    })

    Metrics.observe("treedb_http_request_duration_ms", 12, %{
      method: "GET",
      route: "/api/v1/health"
    })

    Metrics.put_gauge("treedb_workspace_active_count", 2)

    snapshot = Metrics.snapshot()
    assert [%{name: "treedb_http_requests_total", value: 1}] = snapshot.counters
    assert [%{count: 1, sum: 12, buckets: buckets}] = snapshot.histograms
    assert Enum.any?(buckets, &(&1.le == 25 and &1.value == 1))
    assert [%{name: "treedb_workspace_active_count", value: 2}] = snapshot.gauges

    text = Metrics.prometheus()
    assert text =~ "# TYPE treedb_http_requests_total counter"
    assert text =~ "route=\"/api/v1/health\""
  end

  test "scrubs labels before storing metrics" do
    Metrics.incr("treedb_http_errors_total", %{
      method: "GET",
      route: "/tmp/treedb-secret",
      actorId: "actor_1",
      error_code: "permission_denied"
    })

    [counter] = Metrics.snapshot().counters
    refute Map.has_key?(counter.labels, "actor_id")
    refute Map.has_key?(counter.labels, "code")
    assert counter.labels["route"] == "redacted"
    assert counter.labels["error_code"] == "permission_denied"
  end

  test "records domain metrics from audit event boundaries" do
    for {event, metric} <- [
          {"repo.registered", "treedb_repo_operations_total"},
          {"git.push.completed", "treedb_git_remote_operations_total"},
          {"workspace.created", "treedb_workspace_operations_total"},
          {"exec.completed", "treedb_exec_runs_total"},
          {"graph.refreshed", "treedb_graph_refresh_total"},
          {"search.index_refreshed", "treedb_search_index_operations_total"},
          {"snapshot.built", "treedb_snapshot_build_total"},
          {"artifact.exported", "treedb_artifact_operations_total"},
          {"mirror.sync.completed", "treedb_mirror_sync_total"},
          {"federated.search.completed", "treedb_federated_operations_total"},
          {"storage.backup_created", "treedb_storage_operations_total"}
        ] do
      Metrics.record_audit_event(event, %{status: "ok", data: %{elapsedMs: 7, byteLength: 12}})
      assert Enum.any?(Metrics.snapshot().counters, &(&1.name == metric))
    end
  end
end
