# TreeDX

TreeDX is a repository-native API service and storage engine for managing portfolios of Git repositories. It makes repository updates, inspection, indexing, mirroring, placement, and federated query workflows available through a no-clone HTTP API for workers, agents, SDKs, and applications.

TreeDX is intentionally generic. It stores and operates on Git/repository primitives such as repositories, refs, commits, trees, blobs, paths, workspaces, mirrors, nodes, placements, audit events, and indexes. Product-specific concepts from TreeSeed or any other application belong outside TreeDX.

## For Users

Use TreeDX when you need a service that can store, inspect, index, query, snapshot, mirror, and federate Git repositories without repeatedly cloning them for every worker or agent.

Treeseed uses TreeDX for repository intelligence and federation through `@treeseed/sdk` and `@treeseed/api`:

- SDK owns the Treeseed integration/client layer.
- API owns public TreeDX federation hosting inside Treeseed deployments.
- Admin and Market may display repository-backed results, but they do not own TreeDX internals.
- TreeDX remains product-neutral and does not implement Treeseed admin workflows, billing/ecommerce, capacity-provider runtime, assignment policy, agent classes, or market policy.

Quick local start:

```bash
docker compose build treedx-api
docker compose up -d treedx-api
docker compose logs -f treedx-api
```

Treeseed package image workflows use:

```bash
trsd package image --package treedx --branch staging --plan --json
trsd package image --package treedx --branch staging --sync-config --json
trsd package image --package treedx --branch staging --execute --json
```

See the root workspace [Package Ownership](../../docs/package-ownership.md) guide for how TreeDX fits with SDK, API, Admin, Agent, UI, and Market.

## Current Status

TreeDX has a working repository-native API, storage, graph/search/context, snapshot/artifact, audit, registry, SDK, observability, and release verification surface.

Implemented now:

- Docker-based development and production runtime.
- Phoenix JSON API under `apps/api`.
- Rust storage crate under `crates/treedx_store`.
- Rust Git inspection crate under `crates/treedx_git`.
- Rustler NIF wrapper under `apps/api/native/treedx_native`.
- TreeDX-native append-only `.tdb` catalog files with BLAKE3 payload checksums.
- Dev-token authentication for local development.
- Effective capability scope resolution.
- Local node, registry, repository placement, mirror, and audit records.
- Repository registration with Git path validation.
- gix-backed repository status, ref, remote, ref resolution, tree, and blob primitives.
- Workspace session creation, lookup, close, expiration cleanup, and writable branch leases.
- Workspace File API for tree listing, UTF-8 file read/write/patch/delete, search, status, diff, and commit.
- Binary-safe repository and workspace blob APIs, raw upload/download, multipart upload sessions, byte limits, content hashes, and artifact lifecycle management.
- Overlay write model: base reads come from Git objects, workspace writes live in TreeDX-native overlay records and blobs, and commit synthesizes a Git commit from base tree plus overlay changes.
- External Rust `treedx_git_worker` for overlay commits, keeping risky Git object writes out of the BEAM OS process while still using gix and no shell-Git default path.
- Explicit exec backends for local development, Docker container sandboxing, and signed external worker/microVM-profile execution.
- Repository query APIs for generic Git-object-backed read, path list, search, section/link, and changed-path queries that map cleanly to SDK content usage.
- Single-repository graph and context APIs with TreeDX-native graph segments, generic SDK-compatible node/edge shapes, authorization-aware graph filtering, graph refresh jobs, search index status/compaction, graph search/query, related/subgraph traversal, context modes, context packs, and `ctx` DSL parsing.
- Federation-aware global search, query, context, and graph execution with authorization scope reduction, local and HTTP remote routing, deterministic merge, and sanitized partial failures.
- OpenAPI contract coverage for SDK clients that are maintained and tested independently from this TreeDX service repository.
- Connected auth with verifier abstraction, HS256 development compatibility, JWKS/OIDC verification, key rotation/cache behavior, scoped capability grants, policy refresh/revocation, workspace quarantine, and audit event listing.
- Repository snapshots, tar.zst artifact export/download, artifact listing/deletion/cleanup, gix-backed mirror sync, push/fetch workflows, placement migration records, and SDK client methods for those surfaces.
- Storage health/check/recover, compaction, backup, migration, guarded restore verification/apply, retention records, and release-gated recovery checks.
- Public liveness/readiness/deep-health and metrics endpoints, protected deep health, scrubbed production JSON logging, and strict release-gate scripts.
- End-to-end contract verification with in-process Phoenix scenarios, generated OpenAPI fixtures, TreeDX release-gate scripts, container smoke checks, and optional live HTTP checks.

## Why TreeDX Exists

TreeDX is meant to prove this product-level claim:

> TreeDX lets workers, agents, and applications scale across machines without cloning large repositories repeatedly, while preserving efficient Git updates, repository-level federation, auditable operations, access-controlled query, and strongly Git-aligned storage semantics.

The core design choices are:

- Use Git concepts as first-class database primitives.
- Keep TreeDX-owned metadata in an explicit TreeDX data directory.
- Use Rust and Gitoxide/gix for repository operations where practical.
- Use Elixir/Phoenix for HTTP boundaries, supervision, lifecycle, and API coordination.
- Avoid PostgreSQL, SQLite, Ecto, and shell Git as default implementation foundations.
- Keep product and commerce semantics outside TreeDX.

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
    treedx_store/                # Native data directory, catalogs, logs, policy, audit
    treedx_git/                  # gix-backed repository inspection
    treedx_graph/                # Generic graph segments, ranking, and context packs
  docs/
    architecture/                # Current system architecture and risk docs
    runbooks/                    # Operations, recovery, release, and security runbooks
    research/                    # Historical compatibility research and design background
  LICENSE
```

The TypeScript SDK is intentionally tested and released independently from this TreeDX service repository. The top-level TreeDX release gate does not require `packages/ts-sdk`, npm, or Node setup.

## Treeseed Reconciliation Integration

TreeDX owns the implementation, release gate, Docker image workflows, generated SDK publication, and profiler image gates. Treeseed API hosting consumes TreeDX through the SDK-owned reconciliation platform documented in the root workspace `docs/reconciliation-platform.md`.

- `treeseed.package.yaml` declares the TreeDX repository, image target, source-build policy, production image workflow, credential needs, and hosting integration.
- Tagged release images are cut only from merges to `main`.
- Staging builds TreeDX from GitHub source at an exact commit through Railway reconciliation.
- `trsd package image --package treedx --branch staging --plan --json` reports source-build behavior; production image publication uses semantic release tags from `main`.
- `packages/api` owns public TreeDX federation hosting and reconciles the selected source build or production image into Railway services, domains, variables, and volumes.

## Architecture

TreeDX is split into three layers.

```text
HTTP clients / SDKs / agents
  |
  v
TreeDX API service
  - Phoenix JSON API
  - authentication and capability checks
  - repository registration and routing
  - node, registry, placement, mirror, and audit contexts
  - lifecycle supervision for workspace, graph, mirror, exec, observability, and release-gate work
  |
  v
Rust core
  - treedx_store: append-only native records, manifests, recovery, policy, audit
  - treedx_git: gix-backed repository inspection and overlay commit worker
  - treedx_graph: repository graph/search/context indexing
  |
  v
TreeDX data directory
  - catalog files
  - repository metadata
  - bare repository storage
  - workspaces
  - graph/search snapshots
  - placement, mirror, audit, and recovery files
```

### Elixir Responsibilities

Elixir owns process boundaries and lifecycle concerns:

- `TreeDx.Auth`: dev-token authentication, connected JWT verification, JWKS/OIDC verification, and verifier cache behavior.
- `TreeDx.Capabilities`: effective scoped capabilities.
- `TreeDx.Store`: data directory and native storage wrappers.
- `TreeDx.Repos`: repository registration and status.
- `TreeDx.Registry`: node, placement, and mirror records.
- `TreeDx.Git`: Git inspection wrapper.
- `TreeDx.Audit`: append-only audit events.
- `TreeDx.Workspaces`: workspace sessions, base commit snapshots, and writable leases.
- `TreeDx.Files`: workspace-scoped tree, file, search, status, diff, and commit API orchestration.
- `TreeDx.RepositoryQuery`: repository-scoped read, path list, search, section/link, and changed-path query orchestration.
- `TreeDx.Graph`: graph refresh, graph search/query, related/subgraph traversal, context packs, and DSL parsing.
- `TreeDx.Exec`: capability-gated workspace command execution through explicit direct, container, and worker-backed backends.
- `TreeDx.Blobs` and upload controllers: binary-safe repository/workspace blob transport and multipart uploads.
- `TreeDx.Snapshots` and `TreeDx.Artifacts`: repository snapshot build, artifact export/download, listing, deletion, and cleanup.
- `TreeDx.Mirrors` and `TreeDx.Pushes`: registry mirror creation/listing, gix-backed sync orchestration, push planning/execution, and sanitized remote metadata.
- `TreeDx.Migrations`: dry-run and committed placement migration planning.
- `TreeDx.AdminStorage`: storage health, recursive checks, compaction, backup, migration, guarded restore verification, and restore apply gates.
- `TreeDx.Federation`: global search/query/context/graph planning, routing, execution, and result merge.
- `TreeDx.Observability`: scrubber, in-memory metrics, telemetry handlers, health checks, and production JSON log formatting.
- `TreeDx.ConfigValidation`: production boot and release-gate environment validation.

### Rust Responsibilities

Rust crates are function libraries with explicit inputs and outputs:

- `treedx_store` handles `.tdb` append logs, record encoding, checksums, replay, manifests, dev seed records, capabilities, placements, mirrors, tokens, uploads, artifacts, backup/recovery metadata, migration records, and audit events.
- `treedx_git` uses `gix` for repository opening/inspection, tree/blob reads, recursive tree listing, overlay commit synthesis, changed-path comparison, network fetch, and local/file push workflows. Authenticated external transport is opt-in and credential-ID based.
- `treedx_graph` builds generic file, section, tag, reference, and provenance graphs; writes verified graph segment files; ranks lexical/graph-neighborhood matches; and assembles context packs.
- `treedx_native` exposes bounded trusted operations to Elixir through Rustler.

Rustler is used for small and bounded trusted calls. It does not provide OS-process crash isolation for segmentation faults in native code. Risky or long-running work uses explicit process or worker boundaries, including the external Rust commit worker and the exec worker protocol.

## Data Directory

TreeDX initializes `$TREEDX_DATA_DIR`, defaulting to `/var/lib/treedx` in containers.

TreeDX creates:

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

TreeDX-owned records are append-only `.tdb` files. Each file starts with a header:

```text
# treedx:<record-kind>:v1
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

`payloadHash` is BLAKE3 over canonical JSON bytes for the payload. Replay verifies hashes and keeps the latest `put` for each record unless a newer `delete` exists.

Workspace file overlays are recorded in `workspaces/files.tdb`. UTF-8 overlay content is stored under:

```text
workspaces/active/<workspace_id>/overlay/blobs/<blake3_hex>
```

Reads resolve `overlay first, then base Git tree`. Deletes are overlay tombstones. Commit keeps overlay records for audit/debug inspection, marks the workspace committed, and releases the writable lease.

Graph refresh writes TreeDX-native graph segment files under:

```text
graph/repos/<repo_id>/<graph_version>/
  manifest.tdb
  documents.tdb
  nodes.tdb
  edges.tdb
graph/repos/<repo_id>/latest/<ref_hash>.tdb
```

Graph segment records use the same inspectable `.tdb` envelope pattern with BLAKE3 payload hashes. API responses expose logical graph locators such as `treedx://graph/<repo_id>/<graph_version>`, never local segment filesystem paths.

Snapshot build writes repository artifacts under:

```text
snapshots/<snapshot_id>/
  manifest.tdb
  artifact.tar.zst
snapshots/snapshots.tdb
snapshots/artifacts.tdb
```

Artifact responses expose logical URIs such as `treedx://artifact/<snapshot_id>` and optional authenticated download URLs. They never expose local artifact filesystem paths.

## Quick Start

The canonical development path is Docker Compose.

```bash
docker compose build treedx-api
docker compose up -d treedx-api
curl -fsS http://localhost:4000/api/v1/health
```

The first container boot compiles the Rust NIF and may take a little while. Check logs with:

```bash
docker compose logs -f treedx-api
```

Stop the service:

```bash
docker compose down
```

Run a full local performance profile:

```bash
scripts/profile-compose.sh portfolio
```

This starts a local TreeDX API service and a separate profiler service. The
profiler waits for API health, then runs growing portfolio mode against all
scenarios and the endpoint matrix with the default small scale workload:

- load mode: `portfolio`
- fixture: `small-docs`
- scenario: `all`
- size: `small`
- iterations: unset by default for duration-controlled profiles
- concurrency: `100`
- duration: `10m` of measured load after setup completes
- report format: `both`
- admin/destructive/exec/federation operations: enabled inside the isolated
  profiling volume

Reports are written to timestamped paths:

```text
target/profiles/portfolio-<timestamp>.yaml
target/profiles/portfolio-<timestamp>.md
target/profiles/portfolio-<timestamp>-replay.jsonl
target/profiles/portfolio-<timestamp>-failures.jsonl
```

Check a specific result:

```bash
grep -E "totalErrors: 0|failed: 0|unaccounted: 0" target/profiles/portfolio-*.yaml
```

Repeatable profile modes:

```bash
scripts/profile-compose.sh smoke
scripts/profile-compose.sh fixed
scripts/profile-compose.sh portfolio
scripts/profile-compose.sh read-heavy
scripts/profile-compose.sh write-heavy
scripts/profile-compose.sh graph
scripts/profile-compose.sh binary
scripts/profile-compose.sh admin
scripts/profile-compose.sh soak
scripts/profile-compose.sh mirror-federation
scripts/profile-compose.sh connected-library
scripts/profile-compose.sh federation-soak
scripts/profile-compose.sh performance
scripts/profile-compose.sh federation-performance
```

Each mode writes timestamped reports under `target/profiles/` unless
`TREEDX_PROFILE_OUTPUT`, `TREEDX_PROFILE_MARKDOWN_OUTPUT`,
`TREEDX_PROFILE_REPLAY_LOG`, and `TREEDX_PROFILE_FAILURE_REPLAY_LOG` are set.

Duration-based profile modes default to no iteration cap. For example,
`scripts/profile-compose.sh portfolio` runs ten minutes of measured load after
fixture setup completes. If `TREEDX_PROFILE_ITERATIONS` is explicitly set along
with a duration, the profiler stops at whichever limit comes first and reports
whether the measured duration was satisfied.

Normal profile modes run the TreeDX API from the production release image while
keeping dev auth enabled for local token setup. Use `--dev-api` to run the API
through `mix phx.server` for development debugging:

```bash
scripts/profile-compose.sh portfolio --dev-api
```

Federation profile modes start three production-image TreeDX API nodes plus the
profiler. Node A is the profiler ingress, node B and node C join through parent
lineage, and live catalog sync is verified without service restart. The
`mirror-federation` mode checks same-cluster write proxy and mirror reads. The
`connected-library` mode checks remote-owner authorization and confirms writes
are denied by default.

Use `scripts/profile-compose.sh performance` for RPS tuning. It is separate
from the reliability verifier profiles and defaults to a read-mostly portfolio
workload, 150 concurrent workers, 10 minutes of measured load, sampled
validation probes, and a 100 primary RPS target. Reports include both primary
workload RPS and total HTTP RPS; total HTTP includes validation probes and other
measured profiler traffic that affects server load. Tune the benchmark with
`TREEDX_RUNTIME_CPU_BUDGET`, `TREEDX_RUNTIME_MEMORY_BUDGET_MB`,
`TREEDX_CACHE_MEMORY_FRACTION`, and the `TREEDX_*_POOL_SIZE` variables.

Override any workload setting with `TREEDX_PROFILE_*` environment variables:

```bash
TREEDX_PROFILE_SIZE=medium \
TREEDX_PROFILE_CONCURRENCY=100 \
TREEDX_PROFILE_DURATION=30m \
TREEDX_PROFILE_OUTPUT=target/profiles/medium-c100.yaml \
TREEDX_PROFILE_MARKDOWN_OUTPUT=target/profiles/medium-c100.md \
scripts/profile-compose.sh portfolio
```

Clean up generated profiling data with:

```bash
docker compose -f profiles/compose.profile.yaml down -v --remove-orphans
```

See [Performance Profiling](docs/runbooks/performance-profiling.md) and
[TreeDX Profiler](tools/treedx_profiler/README.md) for fixture families,
portfolio growth mode, scenarios, concurrency behavior, and report
interpretation. Verifier profiles also include timing windows, reliability
budget results, OpenAPI response validation, reconciliation summaries, race
classification, and sanitized replay logs.

The development service mounts:

- the repository at `/workspace/treedx`
- the TreeDX data volume at `/var/lib/treedx`

Production image build smoke test:

```bash
docker compose -f compose.prod.yaml build treedx-api
```

The production compose file uses the `prod` Docker target, runs the Phoenix release, sets `TREEDX_AUTH_MODE=connected`, and persists `/var/lib/treedx` in the `treedx-data` volume. Production boot validates insecure settings and fails closed for development auth, development exec, missing verifier configuration, unsafe restore settings, and unconfigured external transport.

## Configuration

Important environment variables:

| Variable | Default | Description |
| --- | --- | --- |
| `TREEDX_DATA_DIR` | `/var/lib/treedx` | TreeDX catalog, audit, workspace, repository, and index data directory. |
| `TREEDX_AUTH_MODE` | `dev` | `dev` enables local dev-token auth. `connected` enables configured verifier authentication and disables dev-token creation. |
| `TREEDX_AUTH_VERIFIER` | `hs256_dev` in development | Connected verifier mode. Production rejects `hs256_dev` unless explicitly overridden. |
| `TREEDX_JWT_ISSUER` | unset | Required JWT issuer in connected auth mode. |
| `TREEDX_JWT_AUDIENCE` | unset | Required JWT audience in connected auth mode. |
| `TREEDX_JWT_HS256_SECRET` | unset | Required HS256 verifier secret in connected auth mode. |
| `TREEDX_JWKS_URL` | unset | JWKS/OIDC key source when using the JWKS verifier. |
| `TREEDX_REGISTRY_MODE` | `local` | Registry mode for node and repository placement records. |
| `TREEDX_NODE_ID` | `node_local` | Local node identifier. |
| `TREEDX_MAX_FILE_BYTES` | `1048576` | Maximum UTF-8 file size for read/write/patch operations. |
| `TREEDX_MAX_BLOB_BYTES` | `10485760` | Maximum decoded JSON blob or raw upload size for single-request blob APIs. |
| `TREEDX_MAX_MULTIPART_BLOB_BYTES` | `536870912` | Maximum completed multipart blob size. |
| `TREEDX_EXEC_BACKEND` | `direct_dev` in development | `direct_dev`, `container_sandbox`, `external_worker`, or `firecracker_or_microvm`. Production rejects `direct_dev` unless explicitly overridden. |
| `TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED` | `false` | Enables the constrained external Git transport for authenticated HTTPS/SSH workflows. |
| `TREEDX_REMOTE_CREDENTIAL_PROVIDER` | `none` | Operator-managed remote credential provider. Public APIs accept credential IDs, never raw secrets. |
| `TREEDX_STORAGE_RESTORE_ENABLED` | `false` | Enables guarded restore operations when paired with explicit acknowledgement and restore mode/force controls. |
| `TREEDX_SNAPSHOT_MAX_FILE_BYTES` | `10485760` | Maximum single file size included in a snapshot artifact. |
| `TREEDX_SNAPSHOT_MAX_TOTAL_BYTES` | `104857600` | Maximum total artifact input size for snapshot build. |
| `PORT` | `4000` | HTTP port for the Phoenix service. |
| `PHX_HOST` | `0.0.0.0` in Compose | Phoenix host binding. |

## API Overview

TreeDX routes are JSON-over-HTTP under `/api/v1`, except raw blob/artifact download responses and the Prometheus text endpoint at `/metrics`. `docs/api/openapi.yaml` is the public contract, and the TypeScript SDK generates TreeDX API types from it.

### Health and Version

```http
GET /api/v1/health
GET /api/v1/ready
GET /api/v1/health/deep
GET /api/v1/admin/health/deep
GET /api/v1/version
GET /api/v1/metrics
GET /metrics
```

Example:

```bash
curl -fsS http://localhost:4000/api/v1/health
curl -fsS http://localhost:4000/api/v1/ready
curl -fsS http://localhost:4000/api/v1/version
curl -fsS http://localhost:4000/metrics
```

`/api/v1/health` is liveness. `/api/v1/ready` is the traffic gate. `/api/v1/health/deep` is a public sanitized summary, and `/api/v1/admin/health/deep` requires `policy:read`. Metrics labels are bounded and scrubbed.

### Authentication

```http
GET  /api/v1/auth/whoami
GET  /api/v1/auth/mode
POST /api/v1/auth/dev-token
```

Create a dev token:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/auth/dev-token \
  -H 'content-type: application/json' \
  -d '{"actorId":"actor_demo","tenantId":"tenant_demo","expiresInSeconds":3600}'
```

The response contains an `accessToken` with the `treedx_dev_` prefix. Use it as a bearer token:

```bash
curl -fsS http://localhost:4000/api/v1/auth/whoami \
  -H "authorization: Bearer $TREEDX_TOKEN"
```

Connected mode uses configured JWT verification. HS256 remains available for development and controlled compatibility; production should use the verifier configuration appropriate to the deployment, such as JWKS/OIDC:

```bash
TREEDX_AUTH_MODE=connected
TREEDX_AUTH_VERIFIER=jwks
TREEDX_JWT_ISSUER=https://issuer.example.invalid
TREEDX_JWT_AUDIENCE=treedx
TREEDX_JWKS_URL=https://issuer.example.invalid/.well-known/jwks.json
```

Required JWT claims are `iss`, `aud`, `sub`, `exp`, and `treedx_tenant_id`. `treedx_actor_id` defaults to `sub` when omitted. Optional `treedx_repo_ids`, `treedx_capabilities`, `treedx_refs`, and `treedx_paths` can further narrow catalog grants.

### Policy

```http
GET  /api/v1/policy/effective-scope
POST /api/v1/policy/refresh
GET  /api/v1/policy/capabilities
GET  /api/v1/policy/grants
POST /api/v1/policy/grants
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
mirror:read
mirror:write
query:federated
policy:read
policy:write
audit:read
```

### Audit And Federation

```http
GET  /api/v1/audit/events
POST /api/v1/federation/query/plan
POST /api/v1/search
POST /api/v1/query
POST /api/v1/context/build
POST /api/v1/graph/query
```

Audit events are stored in TreeDX-native append-only files under `audit/events.tdb`. Event payloads include actor, tenant, repository, node, workspace, operation, status, request ID, requested scope, effective scope, and sanitized metadata. File contents, unsanitized commands, full stdout, and full stderr are not stored by default.

The federation planner is still available for dry-run scope inspection. Global search, query, context, and graph endpoints execute only after reducing requested repository/ref/path scope to the caller's effective authorized scope. Local placements execute in-process; configured remote placements use reduced-scope HTTP routing with sanitized partial-failure responses. Unauthorized repositories, paths, snippets, counts, and graph IDs are not serialized.

Federation is a live routing fabric rather than a separate coordinator service.
Any node can receive a request, resolve the repository or workspace route from
its trusted catalog, execute locally, use a fresh mirror for reads, or proxy to
the trusted primary. Parent lineage bootstraps discovery and catalog sync, but
trust remains explicit and scoped. Internal federation routes require signed
node-to-node tokens and cannot be called with only a normal user bearer token.

TreeDX supports two federation access modes:

- Mirror cluster: same administrative trust domain, shared or replicated auth
  policy, write proxy enabled for trusted primaries, fresh mirrors eligible for
  reads, and manual promotion available for HA.
- Connected library: independently owned repositories, explicit advertisements,
  remote-owner authorization, scoped delegated requests, and write proxy/mirror
  access denied by default.

Federation catalogs contain logical node, repository, route, capacity, and
mirror metadata only. They must not contain local storage paths, credentials,
tokens, hidden paths, snippets, request bodies, stdout/stderr, or binary
payloads.

### Repositories

```http
POST /api/v1/repos
POST /api/v1/repos/register
GET  /api/v1/repos
GET  /api/v1/repos/:repo_id
GET  /api/v1/repos/:repo_id/status
GET  /api/v1/repos/:repo_id/refs
GET  /api/v1/repos/:repo_id/remotes
POST /api/v1/repos/:repo_id/sync
POST /api/v1/repos/:repo_id/push
POST /api/v1/repos/:repo_id/workspaces
```

Create a managed repository:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "repositoryName": "demo-repository",
    "source": {"type": "empty"},
    "placement": {"mode": "local"}
  }'
```

Repository names are canonical lowercase identifiers and are unique in a node's trusted catalog. TreeDX derives repository IDs from the canonical name and stores managed repositories under its configured data directory. Public APIs use repository IDs or names plus repository-relative file paths; public responses do not expose local storage paths.

For controlled local imports, use the admin-only import route with a source path relative to `$TREEDX_DATA_DIR`:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/admin/repos/import-local \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "repositoryName": "demo-repository",
    "sourceRelativePath": "imports/demo-repository"
  }'
```

`POST /api/v1/repos/register` remains as compatibility registration for managed repositories. Normal public usage should not send absolute repository paths.

Repository storage is node-local and managed:

```text
$TREEDX_DATA_DIR/repositories/<repositoryName>
$TREEDX_DATA_DIR/mirrors/<repositoryName>
```

Clients should never address files by absolute host path. All file, blob,
search, graph, snapshot, artifact, and workspace APIs use repository IDs or
names plus paths relative to the repository root.

Get repository status:

```bash
curl -fsS http://localhost:4000/api/v1/repos/$REPO_ID/status \
  -H "authorization: Bearer $TREEDX_TOKEN"
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
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "baseRef": "refs/heads/main",
    "branchName": "refs/heads/agent/demo-task",
    "mode": "writable",
    "allowedPaths": ["docs/**"],
    "ttlSeconds": 1800
  }'
```

Writable workspaces require `workspace:create`, repository write capability, allowed ref/path scope, and primary-node placement. TreeDX permits one active writable lease per repository branch.

Workspace responses include `baseCommitSha` and `commitSha` when applicable. They intentionally do not expose internal workspace materialization paths.

### File And Blob APIs

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
POST   /api/v1/repos/:repo_id/blobs/read
POST   /api/v1/workspaces/:workspace_id/blobs/write
POST   /api/v1/workspaces/:workspace_id/blobs/delete
GET    /api/v1/workspaces/:workspace_id/blobs/download
PUT    /api/v1/workspaces/:workspace_id/blobs/upload
POST   /api/v1/workspaces/:workspace_id/blobs/uploads
PUT    /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id/parts/:part_number
POST   /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id/complete
DELETE /api/v1/workspaces/:workspace_id/blobs/uploads/:upload_id
```

The File API is workspace-scoped and UTF-8-only. Blob APIs are binary-safe and support base64 JSON transport, raw upload/download, multipart uploads, content hashes, byte limits, and conservative content-type detection. Paths are repository-relative POSIX paths. TreeDX rejects absolute paths, encoded or decoded `..`, backslashes, NUL bytes, and protected paths such as `.git/**`, `.ssh/**`, `.env*`, private keys, lockfiles, dependency directories, and build output unless the request explicitly sets `allowProtected=true` and the workspace path scope also allows the path.

Read a file:

```bash
curl -fsS "http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/files?path=docs/readme.md" \
  -H "authorization: Bearer $TREEDX_TOKEN"
```

Write an overlay file:

```bash
curl -fsS -X PUT "http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/files?path=docs/readme.md" \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"encoding":"utf8","content":"Updated through TreeDX\n"}'
```

Search the current workspace view:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/search \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"query":"TreeDX","path":"docs","limit":20}'
```

Commit overlay changes to the workspace branch:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/commit \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{
    "message": "Update repository file through TreeDX",
    "author": {"name": "TreeDX Agent", "email": "agent@example.invalid"}
  }'
```

Commit finalizes the writable workspace: status becomes `committed`, the writable lease is released, further mutations are rejected, and the workspace can still be inspected or closed.

### Exec API

```http
POST /api/v1/workspaces/:workspace_id/exec
```

The Exec API materializes the current workspace view into an internal sandbox directory, runs a policy-checked command with a timeout and output cap, and records an audit event. It does not expose the internal materialized path in normal workspace responses.

Supported modes:

| Mode | Capability | Profile |
| --- | --- | --- |
| `read_only` | `workspace:exec:read_only` | `ls`, `pwd`, `cat`, `sed -n`, `head`, `tail`, `find`, `grep`, `rg`, and read-only `git status/diff/log/show` convenience commands. |
| `verification` | `workspace:exec:verification` | `npm test`, `npm run test`, `npm run typecheck`, `npm run build`, `pnpm test`, `pnpm build`. |
| `write_limited` | `workspace:exec:write_limited` | Explicit writable sessions only; changed UTF-8 files are captured back into the TreeDX overlay and must still be committed through the TreeDX File API. |

Run a read-only command:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/workspaces/$WORKSPACE_ID/exec \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"cmd":"rg \"Decision\" docs | head -20","mode":"read_only","timeoutMs":10000,"maxOutputBytes":60000}'
```

Response shape includes sandbox metadata when a sandbox backend is active:

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

Shell Git mutation commands such as `git push`, `git merge`, and `git rebase` are rejected. TreeDX remains authoritative for status, diff, commit, push, and mirror sync. Production deployments should use `container_sandbox`, `external_worker`, or `firecracker_or_microvm`; `direct_dev` is rejected in production unless explicitly overridden.

### Repository Query API

Repository-level query endpoints operate directly on Git objects. These endpoints are read-only, authorization-filtered, and generic. They parse common repository document structure such as Markdown/MDX frontmatter, headings, links, and changed paths, but they do not understand TreeSeed product models.

```http
POST /api/v1/repos/:repo_id/files/read
POST /api/v1/repos/:repo_id/paths/list
POST /api/v1/repos/:repo_id/files/search
POST /api/v1/repos/:repo_id/query
```

Read a Markdown file with frontmatter and body:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/files/read \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","path":"docs/readme.md","parseFrontmatter":true}'
```

List Markdown and MDX paths:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/paths/list \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"],"extensions":[".md",".mdx"]}'
```

Search text under a path:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/files/search \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"],"query":"release provenance","limit":20}'
```

Filter by generic frontmatter metadata:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/query \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"type":"frontmatter","ref":"refs/heads/main","paths":["docs/**"],"filters":[{"field":"status","op":"eq","value":"published"}]}'
```

Compare changed paths between refs:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/query \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"type":"changed_path","baseRef":"refs/heads/main","ref":"refs/heads/feature","paths":["docs/**"]}'
```

The SDK compatibility seam is intentionally generic: SDK model `contentDir` values map to TreeDX `paths`, SDK filters map to generic fields such as `frontmatter.status`, and the SDK model registry remains responsible for aliases, model names, slugs, and TreeSeed product semantics.

### Graph and Context API

Single-repository graph/context endpoints are backed by TreeDX-native graph segments and refresh job records. Graph refresh indexes authorized text content for a ref, supports incremental changed-path input with safe fallback to full refresh, and feeds search index status/compaction. Markdown/MDX files get generic file nodes, heading section nodes, tag/series metadata nodes, link/reference nodes, and commit/ref provenance nodes.

```http
POST /api/v1/repos/:repo_id/graph/refresh
GET  /api/v1/repos/:repo_id/graph/refresh-jobs/:job_id
POST /api/v1/repos/:repo_id/graph/search-files
POST /api/v1/repos/:repo_id/graph/search-sections
POST /api/v1/repos/:repo_id/graph/search-entities
GET  /api/v1/repos/:repo_id/graph/nodes/:node_id
POST /api/v1/repos/:repo_id/graph/query
POST /api/v1/repos/:repo_id/graph/related
POST /api/v1/repos/:repo_id/graph/subgraph
POST /api/v1/repos/:repo_id/context/build
POST /api/v1/repos/:repo_id/context/parse-ctx
POST /api/v1/repos/:repo_id/search/index/refresh
GET  /api/v1/repos/:repo_id/search/index/status
POST /api/v1/repos/:repo_id/search/index/compact
```

Authorization filtering runs before ranking, traversal, expansion, counting, diagnostics, and serialization. Unauthorized paths and protected paths do not contribute hidden scores, counts, snippets, node IDs, or edge data. Graph nodes are generic SDK-compatible shapes; TreeSeed product model mapping remains outside TreeDX.

Refresh a graph:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/refresh \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","paths":["docs/**"]}'
```

Search sections:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/search-sections \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","limit":20}'
```

Run a graph query:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/graph/query \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","scope":"sections","relations":["references"],"options":{"depth":1,"limit":8}}'
```

Build a context pack:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/context/build \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","query":"release provenance","scope":"sections","budget":{"maxNodes":8,"maxTokens":1800}}'
```

Parse a `ctx` DSL request:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/context/parse-ctx \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"source":"ctx \"release provenance\" for research in /docs via references depth 1 limit 8 budget 1200 as brief"}'
```

### Snapshot, Artifact, Mirror, Push, And Migration API

TreeDX exposes generic repository snapshot, artifact lifecycle, mirror sync, push/fetch, and placement migration endpoints.

```http
POST /api/v1/repos/:repo_id/snapshots/build
GET  /api/v1/repos/:repo_id/snapshots/:snapshot_id
POST /api/v1/repos/:repo_id/artifacts/export
POST /api/v1/repos/:repo_id/artifacts/export?download=true
GET  /api/v1/repos/:repo_id/artifacts
GET  /api/v1/repos/:repo_id/artifacts/:artifact_id
DELETE /api/v1/repos/:repo_id/artifacts/:artifact_id
POST /api/v1/admin/artifacts/cleanup
POST /api/v1/repos/:repo_id/push
POST /api/v1/repos/:repo_id/mirrors/:mirror_id/sync
POST /api/v1/repos/:repo_id/mirrors/:mirror_id/health
POST /api/v1/repos/:repo_id/mirrors/:mirror_id/promote
POST /api/v1/repos/:repo_id/migrations
GET  /api/v1/repos/:repo_id/migrations/:migration_id
```

Snapshot build requires `snapshot:build`, `files:read`, `git:read`, and authorized ref/path scope. Artifact export requires `artifact:export`. Mirror sync requires `mirror:write`, `git:fetch`, and `registry:write`. Migration creation requires `migration:write`, `registry:write`, and `repos:write`.

Build a snapshot:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/snapshots/build \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"ref":"refs/heads/main","kind":"repository_snapshot","paths":["docs/**"],"includeGraph":true}'
```

Export artifact metadata:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/artifacts/export \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"snapshotId":"snap_..."}'
```

Download artifact bytes:

```bash
curl -fsS -X POST 'http://localhost:4000/api/v1/repos/'"$REPO_ID"'/artifacts/export?download=true' \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"snapshotId":"snap_..."}' \
  -o artifact.tar.zst
```

Sync a mirror:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/mirrors/$MIRROR_ID/sync \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"remoteName":"origin","dryRun":false}'
```

Create a migration dry run:

```bash
curl -fsS -X POST http://localhost:4000/api/v1/repos/$REPO_ID/migrations \
  -H "authorization: Bearer $TREEDX_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"targetNodeId":"node_mirror","mode":"primary_transfer","dryRun":true,"requireMirrorSynced":false}'
```

Mirror fetch uses gix network APIs for HTTP(S) and local file remotes. Push supports local path and `file://` remotes through the native path and authenticated HTTPS/SSH through an opt-in constrained external transport. Public requests provide logical `credentialId` values only. Credential-bearing URLs are rejected, SSH requires known hosts, and audit payloads never include raw credentials or full transport output. The published production image keeps the runtime package set small and does not include the shell `git` binary; deployments that enable external Git transport should use a derived image or worker environment that supplies `git` under the same credential and audit controls.

### Admin Storage API

```http
GET  /api/v1/admin/storage/health
POST /api/v1/admin/storage/check
POST /api/v1/admin/storage/recover
POST /api/v1/admin/storage/compact
POST /api/v1/admin/storage/backup
GET  /api/v1/admin/storage/migrations
POST /api/v1/admin/storage/migrations/plan
POST /api/v1/admin/storage/migrations/apply
POST /api/v1/admin/storage/migrations/rollback
POST /api/v1/admin/storage/restore/verify
POST /api/v1/admin/storage/restore
```

Storage administration requires policy capabilities. Responses expose logical IDs, logical log names, and `treedx://backup/...` URIs rather than absolute paths. Restore is disabled unless explicitly enabled and acknowledged, and destructive restore requires recovery mode or `force: true`.

### End-To-End Verification Scenario

The repository includes a repeatable end-to-end proof that runs the main TreeDX repository loop:

- create a dev-token actor
- register fixture repositories
- resolve effective scope and registry placement
- create a writable workspace with a scoped base commit snapshot
- search repository content
- refresh graph data and build context
- plan federation scope reduction and execute authorized global query paths
- write, inspect, diff, and commit a file through the workspace API
- refresh graph data on the committed branch
- build a repository snapshot and export artifact metadata
- create a migration dry-run and exercise storage operations
- inspect audit events
- simulate restart/replay for repository, placement, audit, graph manifest, and snapshot manifest state

The fast in-process scenario lives at:

```text
apps/api/test/treedx_web/end_to_end_mvp_test.exs
```

The optional Docker black-box smoke script runs the same style of loop through HTTP only:

```bash
scripts/mvp-smoke.sh
```

It starts `treedx-api`, waits for readiness, creates a fixture repository inside the container data volume, registers the repo, updates and commits a file, refreshes graph data, builds a snapshot, exports artifact metadata, reads audit events, and prints a concise summary. Set `TREEDX_KEEP_RUNNING=1` to leave the service up after the script exits.

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
| `503` | Service unavailable/readiness failure |
| `500` | Internal error |

## Development

Docker is the supported contributor runtime. Host-local commands are useful for maintainers who already have the required toolchain installed.

Toolchain versions used by the container:

- Elixir `1.17.3`
- Erlang/OTP `27`
- Rust `1.95.0`
- Node `24`
- Phoenix `~> 1.8.7`
- Rustler `0.38.0`
- gix `0.84.0`

### Docker Development

```bash
docker compose up treedx-api
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
docker compose build treedx-api
docker compose up -d treedx-api
curl -fsS http://localhost:4000/api/v1/health
curl -fsS http://localhost:4000/api/v1/auth/whoami
curl -fsS http://localhost:4000/api/v1/node
docker compose exec treedx-api test -d /var/lib/treedx
docker compose exec treedx-api ls -la /var/lib/treedx
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
- End-to-end tests for authenticated repository registration, workspace update/commit, graph/context, federation planning/execution, snapshot/artifact export, migration dry-run, audit coverage, public path hygiene, and restart-style replay.
- OpenAPI server contract tests.
- Security boundary, observability, storage recovery, and release-gate tests.

SDK verification is handled by the SDK package workflow. The TreeDX repository verifies the service, native crates, API contract, container image, storage recovery, and live TreeDX HTTP checks.

## Security Model

Security model:

- `TREEDX_AUTH_MODE=dev` issues local bearer tokens through `/api/v1/auth/dev-token`.
- Tokens are stored as BLAKE3 hashes in TreeDX-native files.
- Effective scope is resolved from seeded capability grants.
- Repository access is capability-scoped by actor, tenant, repo, ref, and path dimensions in the storage model.

- `TREEDX_AUTH_MODE=connected` verifies credentials through configured verifier modules.
- Production identity must not come from request JSON.
- Repository/file/search/graph operations authorize before querying, ranking, traversing, expanding, counting, or serializing results.
- Shell execution is workspace-scoped, capability-gated, audited, timeout-bounded, and environment-scrubbed. Production should use container or worker-backed backends.
- Release readiness is gated by `scripts/release-gate.sh`, which combines TreeDX tests, OpenAPI checks, storage recovery checks, dependency scans, SBOM generation, container scanning, container smoke checks, and optional live federation checks.

Do not use dev tokens as a production authentication mechanism. If you find a vulnerability, use GitHub's private vulnerability reporting or Security Advisories if enabled for the repository. If those are not enabled yet, open a GitHub issue with a minimal non-sensitive description and avoid posting exploitable secrets or private repository details.

## API Stability

TreeDX is pre-1.0. Public compatibility is based on `docs/api/openapi.yaml`, documented error codes, and the release gate. Additive optional fields are allowed when documented; breaking changes require compatibility notes and versioning.

Compatibility priorities:

- Preserve the generic Git/repository database boundary.
- Keep TreeSeed product concepts outside TreeDX.
- Keep storage formats versioned and replayable.
- Keep authorization tied to repository, ref, path, workspace, actor, and tenant scope.
- Keep SDK integration behind explicit local/remote transport ports rather than replacing SDK APIs with raw TreeDX endpoints.

## TreeDX and TreeSeed

TreeDX is designed to support TreeSeed, but it does not encode TreeSeed Market, core, or agent semantics.

TreeDX may store, inspect, index, and query repository files that contain:

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

TreeDX must not understand the product meaning of those concepts. That interpretation belongs in SDK, API, core, market, agent, platform, or control-plane code. Treeseed capacity-provider runners should access TreeDX through project-scoped Treeseed API proxy handles rather than raw TreeDX credentials.

Research notes for the current SDK compatibility target live in:

- `docs/research/environment.md`
- `docs/research/sdk-interface-map.md`
- `docs/research/sdk-baseline-verification.md`

## Operational References

Current architecture and runbooks live under `docs/architecture` and `docs/runbooks`. Start with:

- `docs/api/compatibility-notes.md`
- `docs/architecture/api-contract-versioning.md`
- `docs/architecture/observability-operations.md`
- `docs/architecture/security-model.md`
- `docs/runbooks/release-gate.md`
- `docs/runbooks/operations-health.md`
- `docs/runbooks/metrics.md`
- `docs/runbooks/security-incident.md`

## Contributing

Use GitHub for project coordination:

- Open an issue for bugs, design questions, or proposed changes.
- Open a pull request for implementation work.
- Keep changes scoped to TreeDX's repository/Git/database boundary.
- Do not introduce TreeSeed product-domain concepts into TreeDX core.
- Do not add PostgreSQL, SQLite, Ecto, or a shell-Git default path without an explicit design discussion.
- Include tests for new storage formats, API behavior, and authorization logic.
- Keep SDK changes in the independent SDK workflow unless the task explicitly requires coordinated TreeDX API compatibility work.

Before opening a pull request, run the relevant checks:

```bash
cargo fmt --all -- --check
cargo clippy --workspace -- -D warnings
cargo test --workspace
cd apps/api && mix format --check-formatted && mix test
```

For Docker-facing changes, also run the container smoke verification listed above.

## License

TreeDX is licensed under the Apache License, Version 2.0. See `LICENSE`.
