defmodule TreeDb.Observability.HealthTest do
  use ExUnit.Case, async: false

  alias TreeDb.Observability.Health

  setup do
    previous = Application.get_env(:treedb, :data_dir)
    dir = Path.join(System.tmp_dir!(), "treedb-health-test-#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")

    on_exit(fn ->
      File.rm_rf!(dir)

      if previous,
        do: Application.put_env(:treedb, :data_dir, previous),
        else: Application.delete_env(:treedb, :data_dir)
    end)

    :ok
  end

  test "readiness reports ready for initialized store" do
    readiness = Health.readiness()
    assert readiness.status == "ready"
    assert Enum.any?(readiness.checks, &(&1.name == "storage_replay" and &1.status == "ok"))
    refute Jason.encode!(readiness) =~ TreeDb.Store.data_dir()
  end

  test "readiness can report not ready" do
    readiness = Health.readiness(storage_check: {:ok, %{check: %{status: "error"}}})
    assert readiness.status == "not_ready"
    assert Enum.any?(readiness.checks, &(&1.name == "storage_replay" and &1.status == "failed"))
  end

  test "deep health supports public and detailed sanitized views" do
    public = Health.deep(detailed: false)
    detailed = Health.deep(detailed: true)

    assert Enum.all?(public.checks, &(Map.has_key?(&1, :name) and Map.has_key?(&1, :status)))
    assert Enum.any?(detailed.checks, &Map.has_key?(&1, :details))
    refute Jason.encode!(detailed) =~ TreeDb.Store.data_dir()
  end

  test "auth provider check is optional and sanitized when enabled" do
    previous = System.get_env("TREEDB_HEALTH_CHECK_AUTH_PROVIDER")

    try do
      System.delete_env("TREEDB_HEALTH_CHECK_AUTH_PROVIDER")
      default = Health.deep(detailed: true)
      assert Enum.any?(default.checks, &(&1.name == "auth_provider" and &1.status == "skipped"))

      System.put_env("TREEDB_HEALTH_CHECK_AUTH_PROVIDER", "true")
      enabled = Health.deep(detailed: true)
      auth_check = Enum.find(enabled.checks, &(&1.name == "auth_provider"))
      assert auth_check.status in ["ok", "degraded", "skipped", "failed"]
      refute Jason.encode!(auth_check) =~ "TREEDB_JWKS_URL"
    after
      if previous,
        do: System.put_env("TREEDB_HEALTH_CHECK_AUTH_PROVIDER", previous),
        else: System.delete_env("TREEDB_HEALTH_CHECK_AUTH_PROVIDER")
    end
  end
end
