# Auth, Capability, Federation Access, And Audit Design

This document records the original auth and capability design background.
Current behavior includes JWKS/OIDC verification, policy refresh/revocation,
workspace quarantine, global federation execution, and release-gated security
checks. The current contract is in `docs/api/openapi.yaml`.

## Current Auth State

TreeDB currently supports local development bearer tokens through `POST /api/v1/auth/dev-token`. Tokens are stored only as BLAKE3 hashes in `config/dev_tokens.tdb`, and authenticated callers resolve to a generic principal shape with `actorId`, `tenantId`, and `authMode`.

Connected mode verifies bearer JWTs through configured verifier modules.

## Connected Auth Decision

HS256 remains available for development and controlled compatibility. Production
should use the configured verifier appropriate to the deployment, such as JWKS
or OIDC, and production boot rejects development verifier settings unless
explicitly overridden.

Common connected-mode environment:

- `TREEDB_AUTH_MODE=connected`
- `TREEDB_JWT_ISSUER`
- `TREEDB_JWT_AUDIENCE`
- `TREEDB_JWT_HS256_SECRET`
- `TREEDB_JWKS_URL` when using JWKS verification

Optional:

- `TREEDB_JWT_CLOCK_SKEW_SECONDS`, default `60`

Static opaque tokens were rejected because they do not model user/agent/service
claims well enough. JWKS key discovery, cache refresh, rotation, issuer,
audience, expiry, not-before, clock skew, and algorithm allowlisting are now
covered by verifier modules and tests.

## JWT Claim Contract

Required standard claims:

- `iss`
- `aud`
- `sub`
- `exp`

Supported standard claims:

- `nbf`
- `iat`
- `jti`

TreeDB-scoped claims:

- `treedb_actor_id`
- `treedb_tenant_id`
- optional `treedb_repo_ids`
- optional `treedb_capabilities`
- optional `treedb_refs`
- optional `treedb_paths`

`treedb_actor_id` defaults to `sub` when absent. `treedb_tenant_id` is required. JWT claim scopes may further narrow catalog grants; catalog grants remain authoritative server-side policy.

## Capability Contract

TreeDB uses string capabilities scoped by tenant, repository, ref, and path. The
canonical capabilities include:

```text
repos:read
repos:write
remotes:read
remotes:write
files:read
files:write
files:delete
files:search
graph:refresh
graph:query
workspace:create
workspace:exec:read_only
workspace:exec:verification
workspace:exec:write_limited
git:read
git:diff
git:commit
git:fetch
git:push
snapshot:build
artifact:export
registry:read
registry:write
mirror:read
mirror:write
migration:read
migration:write
query:federated
policy:read
policy:write
audit:read
```

Repo matching supports exact IDs and `*`. Ref matching supports exact refs, `refs/heads/*`, `refs/tags/*`, and `*`. Path matching supports exact paths, `prefix/**`, and `**`.

Workspace records include effective policy metadata. Revocation and policy hash
changes quarantine active workspaces whose live policy no longer authorizes
their snapshot.

## Federation Access Contract

`POST /api/v1/federation/query/plan` reduces a requested cross-repository scope
to the effective authorized repo/ref/path scope for inspection. Global
`/api/v1/search`, `/api/v1/query`, `/api/v1/context/build`, and
`/api/v1/graph/query` execute only after that scope reduction.

Federated execution must not query every repository and filter afterward. Hidden
repositories and paths must not leak via snippets, counts, ranking signals,
graph node IDs, diagnostics, errors, or unauthorized path names.

## Audit Contract

Audit events use a stable append-only envelope persisted in `audit/events.tdb`:

- `eventType`
- `actorId`
- `tenantId`
- `repoId`
- `nodeId`
- `workspaceId`
- `operation`
- `status`
- `requestId`
- `requestedScope`
- `effectiveScope`
- `data`
- `recordedAt`

Mutation and security-relevant operations should audit status and scope. Auth success/failure writes `auth.verified` and `auth.rejected`. Audit data must not include full file content, unsanitized commands, full stdout, or full stderr by default.

## SDK Boundary

The TypeScript SDK forwards bearer tokens and receives TreeDB API errors as `TreeDbApiError`. SDK callers can inspect auth mode, capabilities, grants, audit events, and federation plans generically.

TreeSeed model names, aliases, market concepts, and product semantics remain outside TreeDB.
