# Exec Sandboxing

TreeDX uses `TreeDx.Exec.Backend` with explicit configured modes:

- `direct_dev`
- `container_sandbox`
- `external_worker`
- `firecracker_or_microvm`

`direct_dev` preserves the local development runner but is explicitly disabled in
connected/prod mode unless `TREEDX_ALLOW_DIRECT_EXEC_IN_PROD=true`.

`container_sandbox` builds a Docker invocation with no network, read-only
container filesystem, clean environment, workspace-scoped mounts, and resource
limits. Responses include sandbox metadata so SDK callers can distinguish dev
and isolated execution.

`external_worker` sends a reduced request to an operator-managed worker over
HTTP. When configured, the request can be signed and contains only
workspace-scoped execution metadata.

`firecracker_or_microvm` uses the same worker protocol with a microVM profile.
TreeDX does not orchestrate Firecracker directly.
