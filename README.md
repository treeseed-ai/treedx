# TreeDB

TreeDB is a repository-native API service and storage engine for managing portfolios of Git repositories. It is designed to make repository updates, inspection, indexing, mirroring, placement, and future federated query workflows efficient without repeatedly cloning large repositories for every worker, agent, or application.

TreeDB is intentionally generic. It stores and operates on Git/repository primitives such as repositories, refs, commits, trees, blobs, paths, workspaces, mirrors, nodes, placements, audit events, and indexes. Product-specific concepts from TreeSeed or any other application belong outside TreeDB.

## Current Status

TreeDB is in early MVP development.

Implemented now:

- Docker-based development and production runtime skeleton.
- Phoenix JSON API under `apps/api`.
- Rust storage crate under `crates/treedb_store`.
- Rust Git inspection crate under `crates/treedb_git`.
- Rustler NIF wrapper under `apps/api/native/treedb_native`.
- TreeDB-native append-only `.tdb` catalog files with BLAKE3 payload checksums.
- Dev-token authentication for local development.
- Effective capability scope resolution.
- Local node, registry, repository placement, mirror, and audit records.
- Repository registration with Git path validation.
- gix-backed repository status, ref, remote, ref resolution, tree, and blob primitives.
- Workspace session creation, lookup, close, expiration cleanup, and writable branch leases.

Not implemented yet:

- File/blob read and write APIs.
- Commit, patch, diff, fetch, push, and mirror sync workflows.
- Graph/search indexing service.
- Sandbox command execution.
- Connected control-plane authentication.
- SDK transport integration.

## Why TreeDB Exists

TreeDB is meant to prove this product-level claim:

> TreeDB lets workers, agents, and applications scale across machines without cloning large repositories repeatedly, while preserving efficient Git updates, repository-level federation, auditable operations, access-controlled query, and strongly Git-aligned storage semantics.

The core design choices are:

- Use Git concepts as first-class database primitives.
- Keep TreeDB-owned metadata in an explicit TreeDB data directory.
- Use Rust and Gitoxide/gix for repository operations where practical.
- Use Elixir/Phoenix for HTTP boundaries, supervision, lifecycle, and API coordination.
- Avoid PostgreSQL, SQLite, Ecto, and shell Git as default MVP foundations.
- Keep product and commerce semantics outside TreeDB.

## Repository Layout

```text
.
  Dockerfile
  compose.yaml
  compose.prod.yaml
  Cargo.toml
  apps/
    api/                         # Phoenix API service and Rustler NIF wrapper
  crates/
    treedb_store/                # Native data directory, catalogs, logs, policy, audit
    treedb_git/                  # gix-backed repository inspection
  docs/
    research/                    # Phase 0 compatibility and architecture research
  packages/
    ts-sdk/                      # TreeSeed SDK compatibility target, separate checkout
  PLAN                           # MVP implementation plan
  LICENSE
```

`packages/ts-sdk` is included for research and future compatibility work. Phase 1 does not modify it.

## Architecture

TreeDB is split into three layers.

```text
HTTP clients / SDKs / agents
  |
  v
TreeDB API service
  - Phoenix JSON API
  - authentication and capability checks
  - repository registration and routing
  - node, registry, placement, mirror, and audit contexts
  - lifecycle supervision for future workspace, graph, mirror, and exec jobs
  |
  v
Rust core
  - treedb_store: append-only native records, manifests, recovery, policy, audit
  - treedb_git: gix-backed repository inspection
  - future treedb_graph: repository graph/search/context indexing
  |
  v
TreeDB data directory
  - catalog files
  - repository metadata
  - bare repository storage
  - workspaces
  - graph/search snapshots
  - placement, mirror, audit, and recovery files
```

### Elixir Responsibilities

Elixir owns process boundaries and lifecycle concerns:

- `TreeDb.Auth`: dev-token authentication and future verifier boundary.
- `TreeDb.Capabilities`: effective scoped capabilities.
- `TreeDb.Store`: data directory and native storage wrappers.
- `TreeDb.Repos`: repository registration and status.
- `TreeDb.Registry`: node, placement, and mirror records.
- `TreeDb.Git`: Git inspection wrapper.
- `TreeDb.Audit`: append-only audit events.
- `TreeDb.Workspaces`, `TreeDb.Files`, `TreeDb.Search`, `TreeDb.Graph`, and `TreeDb.Exec`: placeholders for future phases.

### Rust Responsibilities

Rust crates are function libraries with explicit inputs and outputs:

- `treedb_store` handles `.tdb` append logs, record encoding, checksums, replay, manifests, dev seed records, capabilities, placements, mirrors, tokens, and audit events.
- `treedb_git` uses `gix` for repository opening/inspection and returns structured repository, ref, and remote summaries.
- `treedb_native` exposes bounded trusted operations to Elixir through Rustler.

Rustler is used for small and bounded trusted calls. It does not provide OS-process crash isolation for segmentation faults in native code. Future risky or long-running native work should run in an external worker process supervised by Elixir.

## Data Directory

TreeDB initializes `$TREEDB_DATA_DIR`, defaulting to `/var/lib/treedb` in containers.

Phase 1 creates:

```text
catalog/
repos/
repos/bare/
workspaces/
workspaces/active/
leases/
audit/
graph/
search/
snapshots/
federation/
tmp/
recovery/
config/
```

TreeDB-owned records are append-only `.tdb` files. Each file starts with a header:

```text
# treedb:<record-kind>:v1
```

Each following line is a JSON envelope with:

- `schemaVersion`
- monotonic `seq`
- `op`
- `recordKind`
- `recordId`
- `recordedAt`
- `payloadHash`
- `payload`

`payloadHash` is BLAKE3 over canonical JSON bytes for the payload. Replay verifies hashes and keeps the latest `put` for each record unless a later `delete` exists.

## Quick Start

The canonical development path is Docker Compose.

```bash
docker compose build treedb-api
docker compose up -d treedb-api
curl -fsS http://localhost:4000/api/v1/health
```

The first container boot compiles the Rust NIF and may take a little while. Check logs with:

```bash
docker compose logs -f treedb-api
```

Stop the service:

```bash
docker compose down
```

The development service mounts:

- the repository at `/workspace/treedb`
- the TreeDB data volume at `/var/lib/treedb`

Production image build smoke test:

```bash
docker compose -f compose.prod.yaml build treedb-api
```

The production compose file uses the `prod` Docker target, runs the Phoenix release, sets `TREEDB_AUTH_MODE=connected`, and persists `/var/lib/treedb` in the `treedb-data` volume. Connected auth is a future verifier mode, so the production compose file is a deployment skeleton rather than a complete production security configuration.

## Configuration

Important environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `TREEDB_DATA_DIR` | `/var/lib/treedb` | TreeDB catalog, audit, workspace, repository, and index data directory. |
| `TREEDB_AUTH_MODE` | `dev` | `dev` enables local dev-token auth. `connected` is a future verifier mode and currently returns not implemented for dev-token creation. |
| `TREEDB_REGISTRY_MODE` | `local` | Local registry mode for Phase 1. |
| `TREEDB_NODE_ID` | `node_local` | Local node identifier. |
| `PORT` | `4000` | HTTP port for the Phoenix service. |
| `PHX_HOST` | `0.0.0.0` in Compose | Phoenix host binding. |

## API Overview

All Phase 1 routes are JSON-over-HTTP under `/api/v1`.

### Health and Version

```http
GET /api/v1/health
GET /api/v1/version
```

Example:

```bash
curl -fsS http://localhost:4000/api/v1/health
curl -fsS http://localhost:4000/api/v1/version
```

### Authentication

```http
GET  /api/v1/auth/whoami
POST /api/v1/auth/dev-token
```

Create a dev token:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/auth/dev-token \
  -H 'content-type: application/json' \
  -d '{"actorId":"actor_demo","tenantId":"tenant_demo","expiresInSeconds":3600}'
```

The response contains an `accessToken` with the `treedb_dev_` prefix. Use it as a bearer token:

```bash
curl -fsS http://localhost:4000/api/v1/auth/whoami \
  -H "authorization: Bearer $TREEDB_TOKEN"
```

### Policy

```http
GET  /api/v1/policy/effective-scope
POST /api/v1/policy/refresh
```

In dev mode, the default seeded actor is `actor_demo` in `tenant_demo`.

Default dev capabilities:

```text
repos:read
repos:write
files:read
files:write
files:search
graph:query
workspace:create
git:read
git:commit
registry:read
registry:write
```

### Repositories

```http
POST /api/v1/repos/register
GET  /api/v1/repos
GET  /api/v1/repos/:repo_id
GET  /api/v1/repos/:repo_id/status
GET  /api/v1/repos/:repo_id/refs
GET  /api/v1/repos/:repo_id/remotes
POST /api/v1/repos/:repo_id/sync
POST /api/v1/repos/:repo_id/workspaces
```

Register a repository:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/register \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "name": "demo-repository",
    "localPath": "/var/lib/treedb/repos/bare/demo-repository.git",
    "remoteUrl": "https://example.invalid/demo-repository.git",
    "defaultRef": "refs/heads/main"
  }'
```

Repository registration validates that `localPath` is absolute, stays under `$TREEDB_DATA_DIR`, exists, and is a Git repository. The same normalized input produces the same deterministic repository ID. TreeDB keeps `localPath` as internal service setup data and does not return it in public repository response objects.

Get repository status:

```bash
curl -fsS http://localhost:4000/api/v1/repos/$REPO_ID/status \
  -H "authorization: Bearer $TREEDB_TOKEN"
```

If the path does not exist or is not a Git repository, status still returns `200` with structured Git inspection fields such as `exists=false` or `isGitRepository=false`.

### Node and Registry

```http
GET  /api/v1/node
GET  /api/v1/registry/nodes
GET  /api/v1/registry/repos/:repo_id/placement
POST /api/v1/registry/repos/:repo_id/placement
GET  /api/v1/repos/:repo_id/mirrors
POST /api/v1/repos/:repo_id/mirrors
```

`GET /api/v1/node` returns the local node identity. Registry writes and mirror creation require `registry:write`.

### Workspaces

```http
GET  /api/v1/workspaces/:workspace_id
POST /api/v1/workspaces/:workspace_id/close
```

Create a writable workspace:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/workspaces \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "baseRef": "refs/heads/main",
    "branchName": "refs/heads/agent/demo-task",
    "mode": "writable",
    "allowedPaths": ["docs/**"],
    "ttlSeconds": 1800
  }'
```

Writable workspaces require `workspace:create`, repository write capability, allowed ref/path scope, and primary-node placement. Phase 2 permits one active writable lease per repository branch.

## Error Format

Controller errors use a stable JSON shape:

```json
{
  "ok": false,
  "error": {
    "code": "permission_denied",
    "message": "Permission denied.",
    "details": {}
  }
}
```

Common HTTP mappings:

| Status | Meaning |
| --- | --- |
| `400` | Invalid request |
| `401` | Authentication required or invalid token |
| `403` | Permission denied |
| `404` | Not found |
| `409` | Conflict |
| `422` | Validation error |
| `500` | Internal error |
| `501` | Configured mode not implemented |

## Development

Docker is the supported contributor runtime. Host-local commands are useful for maintainers who already have the required toolchain installed.

Phase 1 toolchain versions used by the container:

- Elixir `1.17.3`
- Erlang/OTP `27`
- Rust `1.95.0`
- Node `24`
- Phoenix `~> 1.8.7`
- Rustler `0.38.0`
- gix `0.84.0`

### Docker Development

```bash
docker compose up treedb-api
```

The dev target bind-mounts source code and runs:

```bash
mix deps.get && mix phx.server
```

### Host-Local Checks

From the repository root:

```bash
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
```

Phoenix checks:

```bash
cd apps/api
mix format --check-formatted
mix test
```

Container smoke verification:

```bash
docker compose build treedb-api
docker compose up -d treedb-api
curl -fsS http://localhost:4000/api/v1/health
curl -fsS http://localhost:4000/api/v1/auth/whoami
curl -fsS http://localhost:4000/api/v1/node
docker compose exec treedb-api test -d /var/lib/treedb
docker compose exec treedb-api ls -la /var/lib/treedb
docker compose down
```

## Testing

The project currently has:

- Rust store tests for data-dir initialization, dev seeding, repository records, placement records, mirrors, token records, effective scope, and checksum recovery errors.
- Rust Git tests for missing paths, non-Git directories, non-bare repositories, and bare repositories.
- Rust Git tests for refs, remotes, ref resolution, tree entries, and blob reads.
- Elixir context and controller tests for store initialization, auth, repository registration, repository status, refs/remotes/sync, workspace lifecycle, health/version, policy, registry, and mirror endpoints.

`packages/ts-sdk` has its own baseline state documented in `docs/research/sdk-baseline-verification.md`. Do not treat existing SDK fixture or package graph failures as TreeDB regressions unless the integration work explicitly changes the SDK.

## Security Model

Phase 1 security is development-oriented:

- `TREEDB_AUTH_MODE=dev` issues local bearer tokens through `/api/v1/auth/dev-token`.
- Tokens are stored as BLAKE3 hashes in TreeDB-native files.
- Effective scope is resolved from seeded capability grants.
- Repository access is capability-scoped by actor, tenant, repo, ref, and path dimensions in the storage model.

Production direction:

- `TREEDB_AUTH_MODE=connected` will verify credentials through a control-plane boundary.
- Production identity must not come from request JSON.
- Future repository/file/search operations must authorize before querying or expanding graph/search results.
- Future shell execution must be workspace-scoped, capability-gated, audited, timeout-bounded, and sandboxed.

Do not use dev tokens as a production authentication mechanism. If you find a vulnerability, use GitHub's private vulnerability reporting or Security Advisories if enabled for the repository. If those are not enabled yet, open a GitHub issue with a minimal non-sensitive description and avoid posting exploitable secrets or private repository details.

## API Stability

TreeDB is pre-1.0. API routes, JSON fields, `.tdb` record formats, Docker configuration, and Rust crate APIs may change while the MVP architecture is being finalized.

Compatibility priorities during this phase:

- Preserve the generic Git/repository database boundary.
- Keep TreeSeed product concepts outside TreeDB.
- Keep storage formats versioned and replayable.
- Keep authorization tied to repository, ref, path, workspace, actor, and tenant scope.
- Keep SDK integration behind a future transport seam rather than replacing SDK APIs with raw TreeDB endpoints.

## TreeDB and TreeSeed

TreeDB is designed to support TreeSeed, but it does not encode TreeSeed Market, core, or agent semantics.

TreeDB may store, inspect, index, and query repository files that contain:

- objectives
- questions
- notes
- proposals
- decisions
- agents
- knowledge packs
- templates
- listings
- releases
- platform workflow files

TreeDB must not understand the product meaning of those concepts. That interpretation belongs in SDK, core, market, agent, platform, or control-plane code.

Research notes for the current SDK compatibility target live in:

- `docs/research/environment.md`
- `docs/research/sdk-interface-map.md`
- `docs/research/sdk-baseline-verification.md`

## Roadmap

Near-term work follows the phased MVP plan in `PLAN`.

Expected next areas:

- Repository file/blob APIs.
- Patch, diff, commit, and ref update operations.
- Fetch/push and mirror synchronization.
- Graph/search/index crate and API endpoints.
- Sandboxed exec service.
- Connected auth verifier boundary.
- SDK repository transport seam.
- Production hardening and observability.

## Contributing

Use GitHub for project coordination:

- Open an issue for bugs, design questions, or proposed changes.
- Open a pull request for implementation work.
- Keep changes scoped to TreeDB's repository/Git/database boundary.
- Do not introduce TreeSeed product-domain concepts into TreeDB core.
- Do not add PostgreSQL, SQLite, Ecto, or a shell-Git default path without an explicit design discussion.
- Include tests for new storage formats, API behavior, and authorization logic.
- Preserve `packages/ts-sdk` as a compatibility target unless the task explicitly requires SDK changes.

Before opening a pull request, run the relevant checks:

```bash
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
cd apps/api && mix format --check-formatted && mix test
```

For Docker-facing changes, also run the container smoke verification listed above.

## License

TreeDB is licensed under the Apache License, Version 2.0. See `LICENSE`.
