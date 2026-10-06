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
- `treedx_pool_active`, `treedx_pool_queue_depth`, and
  `treedx_pool_rejections_total`
- `treedx_pool_wait_ms` and `treedx_pool_execution_ms`
- `treedx_cache_hits_total`, `treedx_cache_misses_total`, and
  `treedx_cache_evictions_total`
- `treedx_runtime_beam_memory_bytes` and the configured runtime CPU, memory,
  and cache budgets

Load `observability/prometheus/treedx.rules.yaml` into the Prometheus rule
loader to retain five-minute route RPS, p95/p99 latency, error ratio, and cache
hit-ratio series. The same rules alert on reader/query SLO violations, worker
pool rejection, cache collapse under load, HTTP errors, and audit persistence
failure. Keep these recording series in long-term metrics storage so every
release can be compared with the prior release and the profiler artifacts from
the release gate.

For local validation, run the production profile and retain both generated
reports:

```bash
scripts/profiling/profile-compose.sh performance
```

The default gate is ten minutes at 500 offered primary requests per second,
requires at least 475 delivered primary requests per second, and uses a
four-CPU, 4 GiB service budget. Its hard repository latency ceiling is 900 ms
p99 under saturated load; the 100/250 ms read/query alerts remain the earlier
operational scaling signals. Its YAML report contains route/operation
percentiles, worker-pool wait and execution distributions, cache efficiency,
runtime memory, correctness, and the evaluated reliability budget. Main,
staging, and tagged release-gate runs upload these reports as durable CI
artifacts.

Metrics labels are bounded and sanitized. They must not contain request IDs,
actor IDs, tenant IDs, credentials, raw paths, hidden refs, hidden paths,
snippets, stdout/stderr, or binary payloads.
