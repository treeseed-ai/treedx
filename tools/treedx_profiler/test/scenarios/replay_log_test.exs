defmodule TreeDxProfiler.ReplayLogTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.ReplayLog

  test "writes sanitized request and failure replay logs" do
    root =
      Path.join(System.tmp_dir!(), "treedx-profiler-replay-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(root) end)

    replay = Path.join(root, "replay.jsonl")
    failures = Path.join(root, "failures.jsonl")

    opts = %{request_ledger: true, replay_log: replay, failure_replay_log: failures, seed: "seed"}

    request = %{
      id: "req_1",
      worker_id: 7,
      operation_id: "writeWorkspaceFile",
      seed: "seed",
      expected_status: [200],
      body: %{"content" => "Bearer secret-token"},
      precondition: %{workspace_id: "ws_1"}
    }

    sample = %{
      operation_id: "writeWorkspaceFile",
      method: "PUT",
      path_template: "/api/v1/workspaces/{workspace_id}/files",
      path: "/api/v1/workspaces/ws_1/files",
      status: 409,
      ok: false,
      error_code: "conflict",
      duration_ms: 12.0
    }

    assertion = %{passed: false, error: "conflict"}

    ReplayLog.record(opts, request, sample, assertion)

    assert File.exists?(replay)
    assert File.exists?(failures)
    refute File.read!(replay) =~ "secret-token"
    assert File.read!(replay) =~ "bodyHash"
  end
end
