# Sandbox Exec Runbook

The TreeDX exec runtime makes the exec backend explicit.

## Configuration

```text
TREEDX_EXEC_BACKEND=direct_dev|container_sandbox|external_worker|firecracker_or_microvm
TREEDX_EXEC_CONTAINER_IMAGE=alpine:3.20
TREEDX_EXEC_NETWORK_DEFAULT=none
TREEDX_EXEC_MAX_CPU=1
TREEDX_EXEC_MAX_MEMORY_MB=512
TREEDX_EXEC_MAX_PIDS=64
TREEDX_ALLOW_DIRECT_EXEC_IN_PROD=false
TREEDX_EXEC_WORKER_URL=
TREEDX_EXEC_WORKER_TOKEN=
TREEDX_EXEC_WORKER_HMAC_SECRET=
TREEDX_EXEC_WORKER_TIMEOUT_MS=30000
TREEDX_EXEC_MICROVM_PROFILE=firecracker
```

## Operational Rules

- Dev mode defaults to `direct_dev`.
- Connected/prod mode rejects `direct_dev` unless explicitly overridden.
- `container_sandbox` uses Docker, disables networking by default, uses a clean
  environment, and returns sandbox metadata in the exec response.
- If Docker is not available, exec returns `sandbox_unavailable`.
- Audit events do not include full stdout/stderr or raw command text.
- `write_limited` changes are persisted as UTF-8 or base64 workspace overlays.
- `external_worker` sends a reduced, signed request to an operator-managed worker.
- `firecracker_or_microvm` uses the same worker protocol with a microVM profile. TreeDX does not manage the hypervisor directly.
- Worker failures normalize to `sandbox_unavailable` or `sandbox_policy_denied`.
