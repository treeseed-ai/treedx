# Native Storage Hardening

TreeDX extends the append-only `.tdb` store with:

- recursive log discovery for storage checks
- latest-record compaction for non-audit logs
- logical `tar.zst` backups with checksum metadata
- public admin endpoints for compact and backup operations

Compaction validates JSON log entries, preserves the latest record per
`recordId`, skips audit logs, writes through a temporary file, and atomically
renames the compacted log.

Backups include catalog, policy, audit, graph, snapshots, federation,
workspaces, and leases by default. Public responses expose logical URIs only.
Guarded restore verification and apply are available through admin storage restore endpoints.
