# Git Remote Workflows Runbook

TreeDB provides explicit repository fetch and push operations.

## Push

Use `POST /api/v1/repos/:repo_id/push` with `git:push`.

- Only explicit non-wildcard refspecs are supported.
- Delete refspecs are rejected.
- SSH push is available only when explicitly enabled with credential IDs and strict known_hosts.
- Credential-bearing URLs are rejected.
- Public responses and audit payloads redact local/file remote paths.
- Non-dry-run push supports local path and `file://` remotes through the native
  path.
- Authenticated HTTPS and SSH push/fetch require `credentialId` and
  `TREEDB_GIT_EXTERNAL_TRANSPORT_ENABLED=true`.
- SSH also requires `TREEDB_GIT_SSH_ENABLED=true` and
  `TREEDB_GIT_SSH_KNOWN_HOSTS`.
- The published production image does not include the shell `git` binary. Native
  local and `file://` push paths continue to work without it. Deployments that
  enable authenticated external transport should provide `git` in a derived
  image or operator-managed worker environment.

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
