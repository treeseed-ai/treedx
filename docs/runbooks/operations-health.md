# TreeDB Health Runbook

Use the endpoints by purpose:

- `/api/v1/health`: process liveness.
- `/api/v1/ready`: traffic readiness.
- `/api/v1/health/deep`: public sanitized health summary.
- `/api/v1/admin/health/deep`: protected detailed diagnostics requiring
  `policy:read`.

Readiness failures return `service_unavailable` with failed check names. Deep
health failures include sanitized details only. If storage checks fail, run:

```bash
curl -X POST -H "authorization: Bearer $TOKEN" "$TREEDB_URL/api/v1/admin/storage/check"
```

Never copy raw data directory paths, credentials, snippets, or command output
into incident tickets unless they have been separately scrubbed.
