# Backup and Recovery Runbook

TreeDX provides diagnostic compaction, logical backup creation, backup
verification, migration records, and guarded restore operations.

## Health and Check

Use:

- `GET /api/v1/admin/storage/health`
- `POST /api/v1/admin/storage/check`

Responses use logical/redacted paths only.

## Compact

Use `POST /api/v1/admin/storage/compact` with `policy:write`.

- Audit logs are never compacted.
- Latest-record logs are compacted by record ID.
- `dryRun: true` reports planned file statistics without rewriting logs.
- `backupBefore` defaults to true for non-dry-run compaction.

## Backup

Use `POST /api/v1/admin/storage/backup` with `policy:read`.

Backups are `tar.zst` archives under the TreeDX recovery area, but public
responses return only `treedx://backup/<backup_id>` logical URIs.

The archive is verified by decoding and reading all entries when `verify` is
true.

## Migration and Restore

Use:

- `GET /api/v1/admin/storage/migrations`
- `POST /api/v1/admin/storage/migrations/plan`
- `POST /api/v1/admin/storage/migrations/apply`
- `POST /api/v1/admin/storage/migrations/rollback`
- `POST /api/v1/admin/storage/restore/verify`
- `POST /api/v1/admin/storage/restore`

Migration planning is read-only. Applying a migration records logical migration
metadata and takes a backup by default. Restore verification is non-destructive
and returns logical status. Restore apply is disabled unless
`TREEDX_STORAGE_RESTORE_ENABLED=true`; destructive restore also requires
`TREEDX_STORAGE_MODE=read_only_recovery` or `force: true`.
