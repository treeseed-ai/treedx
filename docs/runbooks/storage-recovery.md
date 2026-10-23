# Storage Recovery Runbook

1. Run protected health and check:

```bash
curl -H "authorization: Bearer $TOKEN" "$TREEDX_URL/api/v1/admin/storage/health"
curl -X POST -H "authorization: Bearer $TOKEN" "$TREEDX_URL/api/v1/admin/storage/check"
```

2. Create and verify a backup:

```bash
curl -X POST -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"verify":true}' \
  "$TREEDX_URL/api/v1/admin/storage/backup"
```

3. Verify restore before applying:

```bash
curl -X POST -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"backupId":"backup_..."}' \
  "$TREEDX_URL/api/v1/admin/storage/restore/verify"
```

4. Apply restore only in recovery mode or with explicit force and
   `TREEDX_STORAGE_RESTORE_ENABLED=true`.

Public responses must contain logical IDs and `treedx://backup/...` URIs only.

## Interrupted registered log

If startup reports an EOF in the final record of a registered log, such as
`catalog/connected_tokens.tdb` or `audit/events.tdb`,
stop the affected managed TreeDX service through its host owner first. Preserve
the data volume and failed startup evidence. The connected-token table records
seen-token metadata; the JWT verifier remains responsible for authentication.
Audit recovery preserves every complete event and the full damaged original;
it does not compact or erase audit history.

The existing runtime image includes `bin/treedx_store_recover`. With the original
data directory mounted and the service stopped, run it as that directory's owner:

```bash
bin/treedx_store_recover /var/lib/treedx catalog/connected_tokens.tdb
bin/treedx_store_recover /var/lib/treedx catalog/connected_tokens.tdb --apply 'blake3:EXACT_DIGEST_FROM_PLAN'
```

The first command only reads and takes the existing `.treedx.lock`; the service
entrypoint holds the same lock. Apply requires the unchanged digest, validates
every complete record and checksum using the original store registry, preserves every original byte under
`recovery/backups`, and atomically installs only the verified complete prefix.
The incomplete record remains an unknown failed observation in that backup.
Unregistered paths, interior corruption, checksum/kind failures, changed input and concurrent service
access are refused. The command never prints record payloads or changes other logs,
workspaces, Git products or claims. Restart through the host owner and verify
readiness and exact workspace/product read-back afterward. Recovery does not prove
the interrupted request succeeded or repair the cause of log growth.
