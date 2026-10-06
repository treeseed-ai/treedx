defmodule TreeDx.Observability.HealthTest do
  use ExUnit.Case, async: false

  alias TreeDx.Observability.Health

  setup do
    previous = Application.get_env(:treedx, :data_dir)
    dir = Path.join(System.tmp_dir!(), "treedx-health-test-#{System.unique_integer([:positive])}")
    remove_dir(dir)
    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")

    on_exit(fn ->
      remove_dir(dir)

      if previous,
        do: Application.put_env(:treedx, :data_dir, previous),
        else: Application.delete_env(:treedx, :data_dir)
    end)

    :ok
  end

  defp remove_dir(dir, attempts \\ 3)

  defp remove_dir(dir, attempts) do
    case File.rm_rf(dir) do
      {:ok, _files} ->
        :ok

      {:error, _reason, _file} when attempts > 0 ->
        Process.sleep(25)
        remove_dir(dir, attempts - 1)

      {:error, reason, file} ->
        raise File.Error, reason: reason, action: "remove directory recursively", path: file
    end
  end

  test "readiness reports ready for initialized store" do
    readiness = Health.readiness()
    assert readiness.status == "ready"
    assert Enum.any?(readiness.checks, &(&1.name == "storage_replay" and &1.status == "ok"))
    refute Jason.encode!(readiness) =~ TreeDx.Store.data_dir()
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
    refute Jason.encode!(detailed) =~ TreeDx.Store.data_dir()
  end

  test "auth provider check is optional and sanitized when enabled" do
    previous = System.get_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER")

    try do
      System.delete_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER")
      default = Health.deep(detailed: true)
      assert Enum.any?(default.checks, &(&1.name == "auth_provider" and &1.status == "skipped"))

      System.put_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER", "true")
      enabled = Health.deep(detailed: true)
      auth_check = Enum.find(enabled.checks, &(&1.name == "auth_provider"))
      assert auth_check.status in ["ok", "degraded", "skipped", "failed"]
      refute Jason.encode!(auth_check) =~ "TREEDX_JWKS_URL"
    after
      if previous,
        do: System.put_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER", previous),
        else: System.delete_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER")
    end
  end
end
