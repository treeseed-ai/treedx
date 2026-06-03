defmodule TreeDb.Observability.JsonLogFormatterTest do
  use ExUnit.Case, async: true

  alias TreeDb.Observability.JsonLogFormatter

  test "formats scrubbed single-line JSON" do
    line =
      JsonLogFormatter.format(
        :info,
        "request_completed",
        {{2026, 6, 3}, {12, 0, 0, 123}},
        request_id: "req_1",
        actor_id: "actor_1",
        tenant_id: "tenant_1",
        repo_id: "repo_1",
        workspace_id: "ws_1",
        duration_ms: 12,
        authorization: "Bearer secret",
        path: "/var/lib/treedb/catalog",
        params: %{secret: "do-not-log"},
        stdout: "do-not-log"
      )
      |> IO.iodata_to_binary()

    payload = Jason.decode!(line)
    assert payload["level"] == "info"
    assert payload["message"] == "request_completed"
    assert payload["requestId"] == "req_1"
    assert payload["actorId"] == "actor_1"
    assert payload["tenantId"] == "tenant_1"
    assert payload["repoId"] == "repo_1"
    assert payload["workspaceId"] == "ws_1"
    assert payload["durationMs"] == 12
    refute line =~ "Bearer secret"
    refute line =~ "/var/lib/treedb"
    refute line =~ "do-not-log"
    assert String.ends_with?(line, "\n")
  end
end
