# Exec Sandboxing

Stage 3 introduces `TreeDb.Exec.Backend` with three configured modes:

- `direct_dev`
- `container_sandbox`
- `external_worker`

`direct_dev` preserves the local MVP runner but is explicitly disabled in
connected/prod mode unless `TREEDB_ALLOW_DIRECT_EXEC_IN_PROD=true`.

`container_sandbox` builds a Docker invocation with no network, read-only
container filesystem, clean environment, workspace-scoped mounts, and resource
limits. Responses include sandbox metadata so SDK callers can distinguish dev
and isolated execution.

`external_worker` is a reserved mode and currently returns `not_implemented`.
