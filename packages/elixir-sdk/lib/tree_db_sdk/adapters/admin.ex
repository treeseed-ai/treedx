defmodule TreeDbSdk.Admin do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def deep_health(client), do: Common.json_request(client, :get, "/api/v1/admin/health/deep")

  def storage_health(client),
    do: Common.json_request(client, :get, "/api/v1/admin/storage/health")

  def storage_check(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/check", body)

  def storage_recover(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/recover", body)

  def storage_compact(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/compact", body)

  def storage_backup(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/backup", body)

  def storage_migrations(client),
    do: Common.json_request(client, :get, "/api/v1/admin/storage/migrations")

  def storage_migration_plan(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/migrations/plan", body)

  def storage_migration_apply(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/migrations/apply", body)

  def storage_migration_rollback(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/migrations/rollback", body)

  def storage_restore_verify(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/restore/verify", body)

  def storage_restore(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/storage/restore", body)

  def quarantined_workspaces(client),
    do: Common.json_request(client, :get, "/api/v1/admin/workspaces/quarantined")

  def cleanup_artifacts(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/admin/artifacts/cleanup", body)

  def import_local_repo(client, body),
    do: Common.json_request(client, :post, "/api/v1/admin/repos/import-local", body)
end
