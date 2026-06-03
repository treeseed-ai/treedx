# Backup and Recovery Runbook

Stage 3 adds diagnostic compaction and logical backup creation. Public
destructive restore is intentionally deferred.

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

Backups are `tar.zst` archives under the TreeDB recovery area, but public
responses return only `treedb://backup/<backup_id>` logical URIs.

The archive is verified by decoding and reading all entries when `verify` is
true. Public restore remains future work.
