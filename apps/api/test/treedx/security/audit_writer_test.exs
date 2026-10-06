defmodule TreeDx.AuditWriterTest do
  use ExUnit.Case, async: false

  setup do
    :ok = TreeDx.Audit.flush()
    previous = System.get_env("TREEDX_AUDIT_ASYNC")
    previous_data_dir = Application.get_env(:treedx, :data_dir)
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
      close_fixture(dir, previous_data_dir, previous)
    end)

    %{directory: dir, previous_data_dir: previous_data_dir, previous_async: previous}
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

  test "audit persistence runs below request-handler scheduler priority" do
    assert {:priority, :low} =
             TreeDx.Audit.Writer
             |> Process.whereis()
             |> Process.info(:priority)
  end

  test "fixture drains pending native audit writes and restores storage authority before deleting only its allocated directory",
       %{directory: dir, previous_data_dir: previous_data_dir, previous_async: previous} do
    writer = Process.whereis(TreeDx.Audit.Writer)
    assert is_pid(writer)
    assert :ok = :sys.suspend(writer)

    try do
      assert {:ok, _event} =
               TreeDx.Audit.append("repo.files_read", %{
                 actor_id: "actor_demo",
                 tenant_id: "tenant_demo",
                 repo_id: "repo_demo",
                 status: "ok",
                 data: %{path: "docs/pending.md"}
               })
    after
      assert :ok = :sys.resume(writer)
    end

    close_fixture(dir, previous_data_dir, previous)
    assert Application.get_env(:treedx, :data_dir) == previous_data_dir
    assert System.get_env("TREEDX_AUDIT_ASYNC") == previous
    assert %{queue: [], size: 0} = :sys.get_state(writer)
    refute File.exists?(dir)
  end

  defp close_fixture(dir, previous_data_dir, previous) do
    restore_env("TREEDX_AUDIT_ASYNC", previous)
    :ok = TreeDx.Audit.flush()

    if is_nil(previous_data_dir) do
      Application.delete_env(:treedx, :data_dir)
    else
      Application.put_env(:treedx, :data_dir, previous_data_dir)
    end

    File.rm_rf!(dir)
  end

  defp restore_env(_key, nil), do: System.delete_env("TREEDX_AUDIT_ASYNC")
  defp restore_env(key, value), do: System.put_env(key, value)
end
