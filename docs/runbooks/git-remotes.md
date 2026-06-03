# Git Remote Workflows Runbook

Stage 3 adds explicit repository fetch and push operations.

## Push

Use `POST /api/v1/repos/:repo_id/push` with `git:push`.

- Only explicit non-wildcard refspecs are supported.
- Delete refspecs are rejected.
- SSH push is not enabled in Stage 3.
- Credential-bearing URLs are rejected.
- Public responses and audit payloads redact local/file remote paths.
- Non-dry-run push supports local path and `file://` remotes.
- HTTP(S) non-dry-run returns `unsupported_transport` until authenticated
  remote transport is implemented.

## Fetch

Use `POST /api/v1/repos/:repo_id/sync` with `git:fetch`.

Request body can include `remoteName`, `remoteUrl`, `refspecs`, and `dryRun`.
Audit payloads include only sanitized remote metadata and refspec counts.

## Mirror Health and Promotion

Use:

- `POST /api/v1/repos/:repo_id/mirrors/:mirror_id/health`
- `POST /api/v1/repos/:repo_id/mirrors/:mirror_id/promote`

Promotion dry-run requires `migration:read`. Applying promotion requires
`migration:write`.
