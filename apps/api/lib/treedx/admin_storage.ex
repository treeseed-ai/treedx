defmodule TreeDx.AdminStorage do
  @moduledoc false

  def health do
    data_dir = TreeDx.Store.data_dir()

    {:ok,
     %{
       storage: %{
         dataDir: "redacted",
         mode: storage_mode(),
         lockHeld: File.exists?(Path.join(data_dir, ".treedx.lock")),
         manifestPresent: File.exists?(Path.join(data_dir, "catalog/manifest.tdb")),
         replayOk: check_status(data_dir) == "ok",
         nativeLoaded: Code.ensure_loaded?(TreeDx.Native)
       }
     }}
  end

  def check do
    data_dir = TreeDx.Store.data_dir()
    errors = collect_errors(data_dir)
    records_checked = count_records(data_dir)
    logs = known_logs()

    {:ok,
     %{
       check: %{
         status: if(errors == [], do: "ok", else: "error"),
         filesChecked: length(logs),
         recordsChecked: records_checked,
         errors: errors
       }
     }}
  end

  def compact(params, principal, request_id) do
    input = %{
      logs: params["logs"] || [],
      dryRun: params["dryRun"] == true,
      backupBefore: params["backupBefore"] != false
    }

    with {:ok, result} <- TreeDx.Store.compact_storage(input) do
      TreeDx.Audit.append("storage.compacted", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.compact",
        status: "ok",
        request_id: request_id,
        data: %{dryRun: result["dryRun"], fileCount: length(result["files"] || [])}
      })

      {:ok, %{compact: redact_compact(result)}}
    end
  end

  def backup(params, principal, request_id) do
    input = %{
      include: params["include"] || [],
      verify: params["verify"] != false
    }

    with {:ok, result} <- TreeDx.Store.create_backup(input) do
      TreeDx.Audit.append("storage.backup_created", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.backup",
        status: "ok",
        request_id: request_id,
        data: %{backupId: result["backupId"], verified: result["verified"]}
      })

      {:ok, %{backup: result}}
    end
  end

  def migrations do
    {:ok,
     %{
       migrations: read_jsonl("recovery/storage_migrations.tdb"),
       manifest: storage_manifest()
     }}
  end

  def plan_migration(params, principal, request_id) do
    target =
      params["targetVersion"] || System.get_env("TREEDX_STORAGE_FORMAT_VERSION") || "current"

    plan = %{
      migrationId: migration_id(target),
      fromVersion: storage_manifest()["formatVersion"] || "unknown",
      toVersion: target,
      dryRun: true,
      reversible: true,
      logs: known_logs(),
      status: "planned"
    }

    TreeDx.Audit.append("storage.migration_planned", %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      operation: "storage.migration.plan",
      status: "ok",
      request_id: request_id,
      data: %{migrationId: plan.migrationId, logCount: length(plan.logs)}
    })

    {:ok, %{migration: plan}}
  end

  def apply_migration(params, principal, request_id) do
    with {:ok, %{migration: plan}} <- plan_migration(params, principal, request_id),
         {:ok, backup} <- maybe_backup_before(params) do
      record =
        plan
        |> Map.merge(%{
          dryRun: false,
          status: "applied",
          backupId: backup && backup["backupId"],
          startedAt: now(),
          completedAt: now()
        })

      append_jsonl!("recovery/storage_migrations.tdb", "storage_migration", record)
      write_manifest!(record.toVersion, record.migrationId)

      TreeDx.Audit.append("storage.migration_applied", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.migration.apply",
        status: "ok",
        request_id: request_id,
        data: %{migrationId: record.migrationId, backupId: record.backupId}
      })

      {:ok, %{migration: record}}
    end
  end

  def rollback_migration(params, principal, request_id) do
    migration_id = params["migrationId"]

    with true <- is_binary(migration_id) and migration_id != "",
         record when is_map(record) <-
           Enum.find(
             read_jsonl("recovery/storage_migrations.tdb"),
             &(&1["migrationId"] == migration_id)
           ) do
      rollback =
        record
        |> Map.put("status", "rolled_back")
        |> Map.put("completedAt", now())

      append_jsonl!("recovery/storage_migrations.tdb", "storage_migration", rollback)

      TreeDx.Audit.append("storage.migration_rolled_back", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.migration.rollback",
        status: "ok",
        request_id: request_id,
        data: %{migrationId: migration_id}
      })

      {:ok, %{migration: rollback}}
    else
      false -> {:error, %{code: "validation_error", message: "migrationId is required."}}
      nil -> {:error, %{code: "not_found", message: "Migration was not found."}}
    end
  end

  def verify_restore(params, principal, request_id) do
    with {:ok, backup_id} <- backup_id(params),
         {:ok, backup_path} <- backup_path(backup_id),
         true <- File.exists?(backup_path) do
      verified = File.stat!(backup_path).size > 0

      TreeDx.Audit.append("storage.restore_verified", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.restore.verify",
        status: "ok",
        request_id: request_id,
        data: %{backupId: backup_id, verified: verified}
      })

      {:ok,
       %{
         restore: %{
           backupId: backup_id,
           dryRun: true,
           verified: verified,
           uri: "treedx://backup/#{backup_id}"
         }
       }}
    else
      false -> {:error, %{code: "not_found", message: "Backup was not found."}}
      {:error, error} -> {:error, error}
    end
  end

  def restore(params, principal, request_id) do
    with :ok <- restore_enabled?(params),
         :ok <- restore_mode?(params),
         {:ok, %{restore: verify}} <- verify_restore(params, principal, request_id),
         {:ok, pre_backup} <- maybe_pre_restore_backup(params) do
      record = %{
        restoreId: "restore_#{System.unique_integer([:positive])}",
        backupId: verify.backupId,
        dryRun: params["dryRun"] == true,
        backupBeforeRestore: params["backupBeforeRestore"] != false,
        preRestoreBackupId: pre_backup && pre_backup["backupId"],
        status: if(params["dryRun"] == true, do: "verified", else: "restored"),
        startedAt: now(),
        completedAt: now(),
        uri: "treedx://backup/#{verify.backupId}"
      }

      append_jsonl!("recovery/storage_restores.tdb", "storage_restore", record)

      TreeDx.Audit.append("storage.restore_checked", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        operation: "storage.restore",
        status: "ok",
        request_id: request_id,
        data: Map.take(record, [:restoreId, :backupId, :dryRun, :status])
      })

      {:ok, %{restore: record}}
    end
  end

  def recover(params, principal, request_id) do
    force = params["force"] in [true, "true"]

    if storage_mode() == "read_only_recovery" or force do
      with {:ok, result} <- check() do
        TreeDx.Audit.append("storage.recovery_checked", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          operation: "storage.recover",
          status: "ok",
          request_id: request_id,
          data: %{status: result.check.status}
        })

        {:ok, Map.put(result, :recovered, false)}
      end
    else
      {:error,
       %{
         code: "conflict",
         message: "Storage recovery requires read_only_recovery mode or force=true."
       }}
    end
  end

  def storage_mode, do: System.get_env("TREEDX_STORAGE_MODE") || "read_write"

  defp storage_manifest do
    case read_jsonl("recovery/storage_manifest.tdb") do
      [] ->
        %{
          "formatVersion" => "current",
          "schemaVersion" => "current",
          "appliedMigrations" => []
        }

      records ->
        List.last(records)
    end
  end

  defp write_manifest!(version, migration_id) do
    current = storage_manifest()
    applied = Enum.uniq((current["appliedMigrations"] || []) ++ [migration_id])

    append_jsonl!("recovery/storage_manifest.tdb", "storage_manifest", %{
      formatVersion: version,
      schemaVersion: version,
      appliedMigrations: applied,
      updatedAt: now()
    })
  end

  defp maybe_backup_before(%{"backupBefore" => false}), do: {:ok, nil}

  defp maybe_backup_before(_params) do
    case TreeDx.Store.create_backup(%{include: [], verify: true}) do
      {:ok, backup} -> {:ok, backup}
      {:error, error} -> {:error, error}
    end
  end

  defp maybe_pre_restore_backup(%{"backupBeforeRestore" => false}), do: {:ok, nil}
  defp maybe_pre_restore_backup(_params), do: maybe_backup_before(%{})

  defp restore_enabled?(params) do
    if System.get_env("TREEDX_STORAGE_RESTORE_ENABLED") == "true" or params["dryRun"] == true do
      :ok
    else
      {:error, %{code: "permission_denied", message: "Storage restore is disabled."}}
    end
  end

  defp restore_mode?(params) do
    if storage_mode() == "read_only_recovery" or params["force"] == true or
         params["dryRun"] == true do
      :ok
    else
      {:error,
       %{
         code: "conflict",
         message: "Storage restore requires read_only_recovery mode or force=true."
       }}
    end
  end

  defp backup_id(%{"backupId" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp backup_id(_), do: {:error, %{code: "validation_error", message: "backupId is required."}}

  defp backup_path(backup_id) do
    if Regex.match?(~r/^backup_[A-Za-z0-9_-]+$/, backup_id) do
      {:ok,
       Path.join([
         TreeDx.Store.data_dir(),
         "recovery",
         "backups",
         backup_id,
         "treedx-backup.tar.zst"
       ])}
    else
      {:error, %{code: "validation_error", message: "backupId is invalid."}}
    end
  end

  defp migration_id(target),
    do:
      "stmig_#{:crypto.hash(:sha256, target) |> Base.encode16(case: :lower) |> binary_part(0, 16)}"

  defp read_jsonl(relative_path) do
    path = Path.join(TreeDx.Store.data_dir(), relative_path)

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"data" => data}} -> [data]
          {:ok, data} -> [data]
          _ -> []
        end
      end)
    else
      []
    end
  end

  defp append_jsonl!(relative_path, kind, data) do
    path = Path.join(TreeDx.Store.data_dir(), relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{kind: kind, data: data}) <> "\n", [:append])
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp check_status(data_dir), do: if(collect_errors(data_dir) == [], do: "ok", else: "error")

  defp collect_errors(data_dir) do
    known_logs()
    |> Enum.flat_map(fn relative_path ->
      path = Path.join(data_dir, relative_path)

      if File.exists?(path) do
        path
        |> File.stream!()
        |> Stream.with_index(1)
        |> Enum.flat_map(fn {line, line_no} ->
          trimmed = String.trim(line)

          cond do
            trimmed == "" or String.starts_with?(trimmed, "#") ->
              []

            true ->
              case Jason.decode(trimmed) do
                {:ok, _} ->
                  []

                {:error, error} ->
                  [%{file: relative_path, line: line_no, error: Exception.message(error)}]
              end
          end
        end)
      else
        []
      end
    end)
  end

  defp count_records(data_dir) do
    Enum.reduce(known_logs(), 0, fn relative_path, count ->
      path = Path.join(data_dir, relative_path)
      if File.exists?(path), do: count + Enum.count(File.stream!(path)), else: count
    end)
  end

  defp known_logs do
    case TreeDx.Store.list_tdb_logs() do
      {:ok, logs} ->
        logs

      _ ->
        [
          "catalog/manifest.tdb",
          "catalog/repositories.tdb",
          "catalog/capability_grants.tdb",
          "catalog/policy_refreshes.tdb",
          "workspaces/sessions.tdb",
          "workspaces/files.tdb",
          "leases/leases.tdb",
          "audit/events.tdb",
          "federation/placements.tdb",
          "federation/mirrors.tdb",
          "federation/migrations.tdb"
        ]
    end
  end

  defp redact_compact(result) do
    Map.update(result, "files", [], fn files ->
      Enum.map(
        files,
        &Map.take(&1, [
          "file",
          "recordsBefore",
          "recordsAfter",
          "bytesBefore",
          "bytesAfter",
          "compacted"
        ])
      )
    end)
  end
end
