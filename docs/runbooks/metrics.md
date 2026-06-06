# TreeDX Metrics Runbook

Prometheus-compatible metrics:

```bash
curl "$TREEDX_URL/metrics"
```

JSON metrics:

```bash
curl "$TREEDX_URL/api/v1/metrics"
```

Important series include:

- `treedx_http_requests_total`
- `treedx_http_request_duration_ms`
- `treedx_http_errors_total`
- `treedx_auth_attempts_total`
- `treedx_auth_failures_total`
- `treedx_capability_denials_total`
- `treedx_audit_append_failures_total`

Metrics labels are bounded and sanitized. They must not contain request IDs,
actor IDs, tenant IDs, credentials, raw paths, hidden refs, hidden paths,
snippets, stdout/stderr, or binary payloads.
