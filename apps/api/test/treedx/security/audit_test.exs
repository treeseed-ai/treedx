defmodule TreeDx.AuditTest do
  use ExUnit.Case, async: false

  setup do
    dir = Path.join(System.tmp_dir!(), "treedx-audit-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")
    :ok
  end

  test "audit events include extended fields and sanitize content" do
    {:ok, event} =
      TreeDx.Audit.append("file.written", %{
        actor_id: "actor_demo",
        tenant_id: "tenant_demo",
        repo_id: "repo_demo",
        workspace_id: "ws_demo",
        operation: "files.write",
        status: "ok",
        request_id: "req_demo",
        data: %{path: "docs/a.md", content: "secret body"}
      })

    assert event["workspaceId"] == "ws_demo"
    refute Map.has_key?(event["data"], "content")

    principal = %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}

    {:ok, %{events: events}} =
      TreeDx.Audit.list(%{"repoId" => "repo_demo", "eventType" => "file.written"}, principal)

    assert [%{"eventType" => "file.written"}] = events
  end
end
