defmodule TreeDx.Observability.Health do
  @moduledoc false

  alias TreeDx.Observability.Scrubber

  def readiness(opts \\ []) do
    checks = [
      check("application_boot", fn -> :ok end),
      check("data_dir_exists", fn -> exists?(TreeDx.Store.data_dir()) end),
      check("storage_manifest", fn ->
        exists?(Path.join(TreeDx.Store.data_dir(), "catalog/manifest.tdb"))
      end),
      check("storage_lock", fn -> storage_lock_ok?() end),
      check("storage_replay", fn -> storage_replay_ok?(opts) end),
      check("native_loaded", fn ->
        if(Code.ensure_loaded?(TreeDx.Native), do: :ok, else: {:error, %{}})
      end)
    ]

    status =
      if Enum.all?(checks, &(&1.status in ["ok", "skipped"])), do: "ready", else: "not_ready"

    %{status: status, checks: public_checks(checks), checkedAt: now()}
  end

  def deep(opts \\ []) do
    detailed = Keyword.get(opts, :detailed, false)

    checks = [
      check("data_dir_writable", fn -> data_dir_writable?() end),
      check("storage_lock", fn -> storage_lock_ok?() end),
      check("store_replay", fn -> storage_replay_ok?(opts) end),
      check("native_loaded", fn ->
        if(Code.ensure_loaded?(TreeDx.Native), do: :ok, else: {:error, %{}})
      end),
      check("graph_store_readable", fn ->
        exists_or_empty?(Path.join(TreeDx.Store.data_dir(), "graph"))
      end),
      check("repository_placements_readable", fn ->
        exists_or_empty?(Path.join(TreeDx.Store.data_dir(), "federation"))
      end),
      check("audit_append_path", fn ->
        exists_or_empty?(Path.join(TreeDx.Store.data_dir(), "audit"))
      end),
      verifier_check()
    ]

    status =
      cond do
        Enum.any?(checks, &(&1.status == "failed")) -> "unhealthy"
        Enum.any?(checks, &(&1.status == "degraded")) -> "degraded"
        true -> "healthy"
      end

    %{
      status: status,
      checks: if(detailed, do: checks, else: public_checks(checks)),
      checkedAt: now()
    }
  end

  defp check(name, fun) do
    started = System.monotonic_time()

    {status, details} =
      case fun.() do
        :ok -> {"ok", %{}}
        :skipped -> {"skipped", %{}}
        {:ok, details} when is_map(details) -> {"ok", details}
        {:degraded, details} when is_map(details) -> {"degraded", details}
        {:error, details} when is_map(details) -> {"failed", details}
        _ -> {"failed", %{}}
      end

    duration =
      System.monotonic_time()
      |> Kernel.-(started)
      |> System.convert_time_unit(:native, :millisecond)

    %{
      name: name,
      status: status,
      durationMs: duration,
      details: Scrubber.scrub(Map.put(details, :dataDir, "redacted"))
    }
  rescue
    _ ->
      %{name: name, status: "failed", durationMs: 0, details: %{}}
  end

  defp public_checks(checks), do: Enum.map(checks, &Map.take(&1, [:name, :status]))

  defp exists?(path), do: if(File.exists?(path), do: :ok, else: {:error, %{}})
  defp exists_or_empty?(path), do: if(File.exists?(path), do: :ok, else: :skipped)

  defp storage_lock_ok? do
    if TreeDx.AdminStorage.storage_mode() == "read_only_recovery" do
      :skipped
    else
      exists?(Path.join(TreeDx.Store.data_dir(), ".treedx.lock"))
    end
  end

  defp storage_replay_ok?(opts) do
    case Keyword.get(opts, :storage_check) || TreeDx.AdminStorage.check() do
      {:ok, %{check: %{status: "ok"} = check}} ->
        {:ok, %{recordsChecked: check.recordsChecked || 0}}

      {:ok, %{"check" => %{"status" => "ok"} = check}} ->
        {:ok, %{recordsChecked: check["recordsChecked"] || 0}}

      _ ->
        {:error, %{}}
    end
  end

  defp data_dir_writable? do
    path = Path.join(TreeDx.Store.data_dir(), ".health-write-check")
    File.write!(path, "ok")
    File.rm(path)
    :ok
  end

  defp verifier_check do
    if System.get_env("TREEDX_HEALTH_CHECK_AUTH_PROVIDER") == "true" do
      check("auth_provider", fn ->
        try do
          timeout_ms = env_int("TREEDX_HEALTH_CHECK_TIMEOUT_MS", 2_000)

          task =
            Task.async(fn ->
              if TreeDx.Auth.mode() == "connected" do
                case TreeDx.Auth.Connected.validate_config() do
                  :ok ->
                    :ok

                  {:error, error} ->
                    {:degraded, %{code: error[:code] || error["code"] || "auth_not_configured"}}
                end
              else
                :skipped
              end
            end)

          Task.await(task, timeout_ms)
        catch
          :exit, {:timeout, _} -> {:degraded, %{code: "timeout"}}
        end
      end)
    else
      %{name: "auth_provider", status: "skipped", durationMs: 0, details: %{}}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end
end
