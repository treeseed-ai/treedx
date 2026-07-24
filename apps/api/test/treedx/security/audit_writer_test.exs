defmodule TreeDx.AuditWriterTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("TREEDX_AUDIT_ASYNC")
    System.put_env("TREEDX_AUDIT_ASYNC", "true")

    dir =
      Path.join(
        System.tmp_dir!(),
        "treedx-audit-writer-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")

    on_exit(fn ->
      restore_env("TREEDX_AUDIT_ASYNC", previous)
      File.rm_rf!(dir)
    end)

    :ok
  end

  test "async audit append flushes before list" do
    {:ok, _event} =
      TreeDx.Audit.append("repo.files_read", %{
        actor_id: "actor_demo",
        tenant_id: "tenant_demo",
        repo_id: "repo_demo",
        status: "ok",
        data: %{path: "docs/readme.md"}
      })

    principal = %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}
    {:ok, %{events: events}} = TreeDx.Audit.list(%{"repoId" => "repo_demo"}, principal)

    assert Enum.any?(events, &(&1["eventType"] == "repo.files_read"))
  end

  defp restore_env(_key, nil), do: System.delete_env("TREEDX_AUDIT_ASYNC")
  defp restore_env(key, value), do: System.put_env(key, value)
end
