# Exec Worker Boundary

TreeDX supports four exec backend names:

- `direct_dev`
- `container_sandbox`
- `external_worker`
- `firecracker_or_microvm`

`direct_dev` remains development-only in connected/prod mode unless explicitly
allowed. `container_sandbox` uses the Docker CLI with no network by default,
read-only container settings, and configured CPU/memory/pid limits.

`external_worker` and `firecracker_or_microvm` use the same HTTP worker protocol.
TreeDX sends a reduced workspace execution request containing command, mode,
resource limits, network policy, and authorized path scope. TreeDX does not
embed or operate Firecracker directly; the microVM profile is an operator-managed
worker implementation detail.

Worker requests may be signed with `TREEDX_EXEC_WORKER_HMAC_SECRET`. Audit
payloads include backend, isolation metadata, limits, exit status, and byte
counts only. Full stdout/stderr and host paths are not serialized to audit.
