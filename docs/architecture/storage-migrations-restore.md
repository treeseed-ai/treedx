# Storage Migrations And Restore

TreeDB storage remains append-only by default. Storage hardening includes
logical migration records, guarded restore verification, and restore apply
gates.

Admin storage migration endpoints:

- `GET /api/v1/admin/storage/migrations`
- `POST /api/v1/admin/storage/migrations/plan`
- `POST /api/v1/admin/storage/migrations/apply`
- `POST /api/v1/admin/storage/migrations/rollback`

Restore endpoints:

- `POST /api/v1/admin/storage/restore/verify`
- `POST /api/v1/admin/storage/restore`

Restore apply is disabled unless `TREEDB_STORAGE_RESTORE_ENABLED=true` and also
requires recovery mode or explicit `force=true`. Public payloads use logical
backup IDs and `treedb://backup/...` URIs only.

Backup retention is controlled by `TREEDB_BACKUP_RETENTION_COUNT`,
`TREEDB_BACKUP_RETENTION_DAYS`, and optional `TREEDB_BACKUP_REMOTE_DIR`.
