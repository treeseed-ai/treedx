# TreeDB Metrics Runbook

Prometheus-compatible metrics:

```bash
curl "$TREEDB_URL/metrics"
```

JSON metrics:

```bash
curl "$TREEDB_URL/api/v1/metrics"
```

Important series include:

- `treedb_http_requests_total`
- `treedb_http_request_duration_ms`
- `treedb_http_errors_total`
- `treedb_auth_attempts_total`
- `treedb_auth_failures_total`
- `treedb_capability_denials_total`
- `treedb_audit_append_failures_total`

Metrics labels are bounded and sanitized. They must not contain request IDs,
actor IDs, tenant IDs, credentials, raw paths, hidden refs, hidden paths,
snippets, stdout/stderr, or binary payloads.
