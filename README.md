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
- Phase 3 workspace File API for tree listing, UTF-8 file read/write/patch/delete, search, status, diff, and commit.
- Overlay MVP write model: base reads come from Git objects, workspace writes live in TreeDB-native overlay records and blobs, and commit synthesizes a Git commit from base tree plus overlay changes.
- External Rust `treedb_git_worker` for overlay commits, keeping risky Git object writes out of the BEAM OS process while still using gix and no shell-Git default path.
- Phase 4 remote sandbox shell MVP for allowlisted read-only exploration, verification commands, and explicitly writable internal sessions.
- Phase 5 repository query MVP for generic Git-object-backed read, path list, search, section/link, and changed-path queries that map cleanly to SDK content usage.
- Phase 6 single-repository graph and context MVP with TreeDB-native graph segments, generic SDK-compatible node/edge shapes, authorization-aware graph filtering, graph search/query, related/subgraph traversal, context packs, and `ctx` DSL parsing.

Not implemented yet:

- Binary file read/write APIs.
- Fetch, push, and mirror sync workflows.
- Federation-aware global search/query/context routing.
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
    treedb_graph/                # Generic graph segments, ranking, and context packs
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
  - treedb_git: gix-backed repository inspection and overlay commit worker
  - treedb_graph: repository graph/search/context indexing
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
- `TreeDb.Workspaces`: workspace sessions, base commit snapshots, and writable leases.
- `TreeDb.Files`: workspace-scoped tree, file, search, status, diff, and commit API orchestration.
- `TreeDb.RepositoryQuery`: repository-scoped read, path list, search, section/link, and changed-path query orchestration.
- `TreeDb.Graph`: graph refresh, graph search/query, related/subgraph traversal, context packs, and DSL parsing.
- `TreeDb.Exec`: capability-gated workspace command execution.

### Rust Responsibilities

Rust crates are function libraries with explicit inputs and outputs:

- `treedb_store` handles `.tdb` append logs, record encoding, checksums, replay, manifests, dev seed records, capabilities, placements, mirrors, tokens, and audit events.
- `treedb_git` uses `gix` for repository opening/inspection, tree/blob reads, recursive tree listing, and overlay commit synthesis.
- `treedb_graph` builds generic file, section, tag, reference, and provenance graphs; writes verified graph segment files; ranks lexical/graph-neighborhood matches; and assembles context packs.
- `treedb_native` exposes bounded trusted operations to Elixir through Rustler.

Rustler is used for small and bounded trusted calls. It does not provide OS-process crash isolation for segmentation faults in native code. The Phase 3 overlay commit path uses an external Rust worker process for that reason; future risky or long-running native work should follow the same supervised process boundary.

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

Workspace file overlays are recorded in `workspaces/files.tdb`. UTF-8 overlay content is stored under:

```text
workspaces/active/<workspace_id>/overlay/blobs/<blake3_hex>
```

Reads resolve `overlay first, then base Git tree`. Deletes are overlay tombstones. Commit keeps overlay records for audit/debug inspection, marks the workspace committed, and releases the writable lease.

Graph refresh writes TreeDB-native graph segment files under:

```text
graph/repos/<repo_id>/<graph_version>/
  manifest.tdb
  documents.tdb
  nodes.tdb
  edges.tdb
graph/repos/<repo_id>/latest/<ref_hash>.tdb
```

Graph segment records use the same inspectable `.tdb` envelope pattern with BLAKE3 payload hashes. API responses expose logical graph locators such as `treedb://graph/<repo_id>/<graph_version>`, never local segment filesystem paths.

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
| `TREEDB_MAX_FILE_BYTES` | `1048576` | Maximum UTF-8 file size for read/write/patch MVP operations. |
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
graph:refresh
workspace:create
git:read
git:diff
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

Workspace responses include `baseCommitSha` and `commitSha` when applicable. They intentionally do not expose internal workspace materialization paths.

### File API

```http
GET    /api/v1/workspaces/:workspace_id/tree?path=...
GET    /api/v1/workspaces/:workspace_id/files?path=...
PUT    /api/v1/workspaces/:workspace_id/files?path=...
PATCH  /api/v1/workspaces/:workspace_id/files?path=...
DELETE /api/v1/workspaces/:workspace_id/files?path=...
POST   /api/v1/workspaces/:workspace_id/search
GET    /api/v1/workspaces/:workspace_id/status
GET    /api/v1/workspaces/:workspace_id/diff
POST   /api/v1/workspaces/:workspace_id/commit
POST   /api/v1/workspaces/:workspace_id/exec
```

The File API is workspace-scoped and UTF-8-only in Phase 3. Paths are repository-relative POSIX paths. TreeDB rejects absolute paths, `..`, backslashes, NUL bytes, and protected paths such as `.git/**`, `.env*`, private keys, lockfiles, dependency directories, and build output unless the request explicitly sets `allowProtected=true` and the workspace path scope also allows the path.

Read a file:

```bash
curl -fsS "http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/files?path=docs/readme.md" \
  -H "authorization: Bearer $TREEDB_TOKEN"
```

Write an overlay file:

```bash
curl -fsS -X PUT "http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/files?path=docs/readme.md" \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"encoding":"utf8","content":"Updated through TreeDB\n"}'
```

Search the current workspace view:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/search \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"query":"TreeDB","path":"docs","limit":20}'
```

Commit overlay changes to the workspace branch:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/commit \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "message": "Update repository file through TreeDB",
    "author": {"name": "TreeDB Agent", "email": "agent@example.invalid"}
  }'
```

Commit finalizes the writable workspace for the MVP: status becomes `committed`, the writable lease is released, further mutations are rejected, and the workspace can still be inspected or closed.

### Exec API

```http
POST /api/v1/workspaces/:workspace_id/exec
```

The Exec API materializes the current workspace view into an internal sandbox directory, runs a policy-checked command with a timeout and output cap, and records an audit event. It does not expose the internal materialized path in normal workspace responses.

Supported MVP modes:

| Mode | Capability | Profile |
| --- | --- | --- |
| `read_only` | `workspace:exec:read_only` | `ls`, `pwd`, `cat`, `sed -n`, `head`, `tail`, `find`, `grep`, `rg`, and read-only `git status/diff/log/show` convenience commands. |
| `verification` | `workspace:exec:verification` | `npm test`, `npm run test`, `npm run typecheck`, `npm run build`, `pnpm test`, `pnpm build`. |
| `write_limited` | `workspace:exec:write_limited` | Explicit writable sessions only; changed UTF-8 files are captured back into the TreeDB overlay and must still be committed through the TreeDB File API. |

Run a read-only command:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/exec \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"cmd":"rg \"Decision\" docs | head -20","mode":"read_only","timeoutMs":10000,"maxOutputBytes":60000}'
```

Response shape:

```json
{
  "ok": true,
  "exitCode": 0,
  "stdout": "...",
  "stderr": "",
  "elapsedMs": 123,
  "truncated": false,
  "changedPaths": []
}
```

Shell Git mutation commands such as `git push`, `git merge`, and `git rebase` are rejected. TreeDB remains authoritative for status, diff, commit, push, and mirror sync. The Phase 4 sandbox is intended for local development and trusted internal agents; production hosting needs stronger isolation, such as containerized or VM-backed execution, before accepting untrusted commands.

### Repository Query API

Phase 5 adds repository-level query endpoints that operate directly on Git objects. These endpoints are read-only, authorization-filtered, and generic. They parse common repository document structure such as Markdown/MDX frontmatter, headings, links, and changed paths, but they do not understand TreeSeed product models.

```http
POST /api/v1/repos/:repo_id/files/read
POST /api/v1/repos/:repo_id/paths/list
POST /api/v1/repos/:repo_id/files/search
POST /api/v1/repos/:repo_id/query
```

Read a Markdown file with frontmatter and body:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/files/read \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","path":"docs/readme.md","parseFrontmatter":true}'
```

List Markdown and MDX paths:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/paths/list \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"],"extensions":[".md",".mdx"]}'
```

Search text under a path:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/files/search \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"],"query":"release provenance","limit":20}'
```

Filter by generic frontmatter metadata:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/query \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"type":"frontmatter","ref":"refs/heads/main","paths":["docs/**"],"filters":[{"field":"status","op":"eq","value":"published"}]}'
```

Compare changed paths between refs:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/query \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"type":"changed_path","baseRef":"refs/heads/main","ref":"refs/heads/feature","paths":["docs/**"]}'
```

The SDK compatibility seam is intentionally generic: SDK model `contentDir` values map to TreeDB `paths`, SDK filters map to generic fields such as `frontmatter.status`, and the SDK model registry remains responsible for aliases, model names, slugs, and TreeSeed product semantics.

### Graph and Context API

Phase 6 adds single-repository graph/context endpoints backed by TreeDB-native graph segments. Graph refresh indexes authorized UTF-8 `.md`, `.mdx`, and `.txt` files for a ref. Markdown/MDX files get generic file nodes, heading section nodes, tag/series metadata nodes, link/reference nodes, and commit/ref provenance nodes.

```http
POST /api/v1/repos/:repo_id/graph/refresh
POST /api/v1/repos/:repo_id/graph/search-files
POST /api/v1/repos/:repo_id/graph/search-sections
POST /api/v1/repos/:repo_id/graph/search-entities
GET  /api/v1/repos/:repo_id/graph/nodes/:node_id
POST /api/v1/repos/:repo_id/graph/query
POST /api/v1/repos/:repo_id/graph/related
POST /api/v1/repos/:repo_id/graph/subgraph
POST /api/v1/repos/:repo_id/context/build
POST /api/v1/repos/:repo_id/context/parse-ctx
```

Authorization filtering runs before ranking, traversal, expansion, counting, diagnostics, and serialization. Unauthorized paths and protected paths do not contribute hidden scores, counts, snippets, node IDs, or edge data. Graph nodes are generic SDK-compatible shapes; TreeSeed product model mapping remains outside TreeDB.

Refresh a graph:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/refresh \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"]}'
```

Search sections:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/search-sections \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","limit":20}'
```

Run a graph query:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/query \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","scope":"sections","relations":["references"],"options":{"depth":1,"limit":8}}'
```

Build a context pack:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/context/build \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","scope":"sections","budget":{"maxNodes":8,"maxTokens":1800}}'
```

Parse a `ctx` DSL request:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/context/parse-ctx \
  -H "authorization: Bearer $TREEDB_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"source":"ctx \"release provenance\" for research in /docs via references depth 1 limit 8 budget 1200 as brief"}'
```

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
| `413` | Payload too large |
| `415` | Unsupported media type |
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
- Rust Git tests for refs, remotes, ref resolution, tree entries, recursive tree entries, blob reads, and overlay commits.
- Rust store tests for workspace file overlays and committed workspace lease release.
- Rust graph tests for generic graph extraction, deterministic ranking/query behavior, segment write/read, checksum recovery, and `ctx` DSL parsing.
- Elixir context and controller tests for store initialization, auth, repository registration, repository status, refs/remotes/sync, workspace lifecycle, health/version, policy, registry, mirror endpoints, File API workflows, Repository Query workflows, Graph/Context API workflows, and SDK query/graph mapping contracts.

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
- Repository/file/search/graph operations authorize before querying, ranking, traversing, expanding, counting, or serializing results.
- Shell execution is workspace-scoped, capability-gated, audited, timeout-bounded, and environment-scrubbed. The Phase 4 direct-process sandbox is not sufficient for untrusted public execution.

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

- Binary file strategy and larger object streaming.
- Fetch/push and mirror synchronization.
- Federation-aware global search/query/context APIs.
- Stronger sandbox isolation for untrusted exec, such as Docker, gVisor, or Firecracker.
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
