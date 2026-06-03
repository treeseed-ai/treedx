# Sandbox Exec Runbook

Stage 3 makes the exec backend explicit.

## Configuration

```text
TREEDB_EXEC_BACKEND=direct_dev|container_sandbox|external_worker
TREEDB_EXEC_CONTAINER_IMAGE=alpine:3.20
TREEDB_EXEC_NETWORK_DEFAULT=none
TREEDB_EXEC_MAX_CPU=1
TREEDB_EXEC_MAX_MEMORY_MB=512
TREEDB_EXEC_MAX_PIDS=64
TREEDB_ALLOW_DIRECT_EXEC_IN_PROD=false
```

## Operational Rules

- Dev mode defaults to `direct_dev`.
- Connected/prod mode rejects `direct_dev` unless explicitly overridden.
- `container_sandbox` uses Docker, disables networking by default, uses a clean
  environment, and returns sandbox metadata in the exec response.
- If Docker is not available, exec returns `sandbox_unavailable`.
- Audit events do not include full stdout/stderr or raw command text.
- `write_limited` changes are persisted as UTF-8 or base64 workspace overlays.

`external_worker` is reserved for a later isolated execution service.
