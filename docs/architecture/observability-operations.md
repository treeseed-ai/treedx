# TreeDB Observability And Operations

TreeDB exposes operational signals through sanitized health endpoints, in-memory
metrics, protected diagnostics, audit records, and production JSON logs.

## Health Model

- `/api/v1/health` is liveness only and returns a redacted data directory marker.
- `/api/v1/ready` is the traffic gate for load balancers.
- `/api/v1/health/deep` is public and returns sanitized check names/statuses.
- `/api/v1/admin/health/deep` requires `policy:read` and returns more detailed
  sanitized diagnostics.

Deep health checks cover storage lock state, store replay, native module
loading, graph storage readability, repository placement metadata readability,
audit append path availability, and optional auth-provider checks.

## Metrics

TreeDB exposes both:

- `/metrics` for Prometheus text scraping.
- `/api/v1/metrics` for JSON diagnostics.

Metrics labels are intentionally bounded and sanitized. Labels never contain
actor IDs, tenant IDs, tokens, credentials, filesystem paths, snippets,
stdout/stderr, request bodies, or binary payloads.

## Logs

Production logs are single-line JSON records. Local development and tests keep
human-readable console output.

JSON logs include request and operation metadata such as request ID, actor ID,
tenant ID, route, method, status, and duration when available. The formatter
scrubs secret-like values and filesystem paths before serialization.

## Contract

Operational endpoints are part of the public API contract in
`docs/api/openapi.yaml`. SDK types are generated from that contract.
