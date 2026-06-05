# Performance Profiling Runbook

TreeDB includes a standalone API profiler under `tools/treedb_profiler`.

The profiler builds deterministic fixture repositories, registers them through
TreeDB HTTP APIs, performs reads, writes, graph refreshes, context builds,
snapshot/artifact operations, and emits YAML plus optional Markdown reports that
can be compared over time.

## One-Command Local Profile

Use `profiles/compose.profile.yaml` to start TreeDB and run the profiler in one Compose
run:

```bash
scripts/profile-compose.sh portfolio
```

The manifest starts:

- `treedb-api`: local TreeDB API from the production release image, using dev
  auth for turnkey local profiling.
- `treedb-profiler`: profiler client that connects to
  `http://treedb-api:4000`.

Both services share `treedb-data:/var/lib/treedb`. This lets the profiler create
fixture Git repositories under `/var/lib/treedb/profiler`, then register them
through the public API.

Default workload:

- load mode: `portfolio`
- fixture: `small-docs`
- size: `small`
- scenario: `all`
- iterations: unset by default
- concurrency: `100`
- duration: `10m` of measured load after setup completes
- report format: `both`
- reliability verifier: enabled
- admin/destructive/exec/federation operations: enabled inside the isolated
  profiling volume

Reports are written to timestamped paths:

```text
target/profiles/portfolio-<timestamp>.yaml
target/profiles/portfolio-<timestamp>.md
target/profiles/portfolio-<timestamp>-replay.jsonl
target/profiles/portfolio-<timestamp>-failures.jsonl
```

Check the result:

```bash
grep -E "totalErrors: 0|failed: 0|unaccounted: 0" target/profiles/portfolio-*.yaml
```

Override settings with environment variables:

```bash
TREEDB_PROFILE_SIZE=medium \
TREEDB_PROFILE_CONCURRENCY=100 \
TREEDB_PROFILE_DURATION=30m \
TREEDB_PROFILE_OUTPUT=target/profiles/medium-c100.yaml \
TREEDB_PROFILE_MARKDOWN_OUTPUT=target/profiles/medium-c100.md \
scripts/profile-compose.sh portfolio
```

Safety notes:

- The default profile Compose manifest uses the production release image for the
  API and dev auth for local token setup.
- It uses an isolated Compose data volume.
- `docker compose -f profiles/compose.profile.yaml down -v` deletes generated profiling
  data.
- The Compose profile enables destructive routes so it can exercise the full
  local endpoint matrix. It runs against the isolated Compose data volume, not
  shared production data.

## Repeatable Compose Profiles

Use the gateway script for repeatable profile configurations:

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

Modes:

- `smoke`: fast correctness profile with `small-docs`, one iteration, and no destructive/admin/exec/federation routes.
- `fixed`: deterministic fixed-fixture baseline across all canonical fixture families.
- `portfolio`: 10-minute growing portfolio run with concurrency `100`.
- `read-heavy`: medium mixed fixture focused on reads, search, query, and federation reads.
- `write-heavy`: workspace-heavy fixture focused on writes, patches, commits, blobs, snapshots, and exec.
- `graph`: graph-rich fixture focused on graph refresh/query/context/search-index paths.
- `binary`: binary-assets fixture focused on blob, multipart, and artifact lifecycle paths.
- `admin`: small admin/storage diagnostic run with explicit destructive dry-run coverage.
- `soak`: 24-hour growing portfolio run for reliability monitoring.
- `mirror-federation`: three-node mirror-cluster profile with catalog
  convergence, write proxy, mirror reads, and reliability verification.
- `connected-library`: three-node connected-library profile with remote-owner
  authorization, scoped federation reads, and default write-denial checks.
- `federation-soak`: longer three-node federation reliability profile.
- `performance`: single-node read-mostly benchmark with a 100 primary RPS
  target, sampled validation probes, and runtime resource tuning defaults.
- `federation-performance`: three-node federation benchmark using the same
  primary/total throughput reporting and resource tuning defaults.

The script composes `profiles/compose.profile.yaml` with `profiles/compose.profile.<mode>.yaml`,
cleans the profiling volume by default, and writes timestamped YAML and
Markdown reports under `target/profiles/`.

Federation modes use `profiles/compose.profile.federation.yaml` plus the
selected federation overlay. They start three production-image API nodes:
`treedb-node-a`, `treedb-node-b`, and `treedb-node-c`, each with its own data
volume and node identity. Node A is the profiler ingress. Node B and node C use
parent lineage rooted at node A so live catalog sync can discover routes without
restarting services.

Options:

```bash
scripts/profile-compose.sh portfolio --no-clean
scripts/profile-compose.sh read-heavy --no-build
scripts/profile-compose.sh graph --config
scripts/profile-compose.sh portfolio --dev-api
```

Use `--dev-api` only when you want the API service to run through `mix
phx.server` with the repository bind-mounted for development debugging. Normal
profile modes use the production release image.

Duration-based modes do not set a default iteration cap. If
`TREEDB_PROFILE_DURATION=10m` and `TREEDB_PROFILE_ITERATIONS` is unset, the
profiler starts its measured timer after setup and continues load until the
measured window reaches ten minutes. If an explicit iteration cap is supplied
along with a duration, the profiler stops at whichever limit comes first and
records `timing.measured.durationSatisfied` in the report.

Release-path CI uses the same duration semantics for federation profiles:
`TREEDB_CI_FEDERATION_PROFILE_DURATION` defaults to `10m`, and Docker
publishing is blocked unless the mirror and connected-library profiles satisfy
their measured windows and pass the reliability budget.

## Reliability Verifier Output

Verifier mode is enabled by default for compose profiles and CI profile runs.
The report includes:

- `timing`: profile, setup, measured-load, and cleanup start/end/duration.
- `reliabilityBudget`: pass/fail status and violations.
- `modelState` and `reconciliation`: expected API-visible state summaries and drift.
- `openapiValidation`: response/schema validation totals.
- `operationChains`, `negativeTests`, `metamorphic`,
  `endpointConsistency`, `delayedConsistency`, `permissionMatrix`, and
  `leakDetection`.
- `concurrency.raceInterference`: verified and unverified race accounting.
- `replay`: sanitized request-ledger and failure replay-log paths.

The default budget requires zero request errors, semantic failures, OpenAPI
failures, reconciliation drift, unverified races, validation-probe failures,
negative-test failures, metamorphic failures, endpoint-consistency failures,
and delayed-consistency failures. It also fails if the measured duration is
below 99% of the requested duration.

Performance profiles enable these server-side optimization defaults unless
overridden:

- `TREEDB_REPO_DOC_CACHE_ENABLED=true`
- `TREEDB_GRAPH_INDEX_CACHE_ENABLED=true`
- `TREEDB_ARTIFACT_INDEX_ENABLED=true`
- `TREEDB_AUDIT_ASYNC=true`

## Performance Benchmark Mode

Use performance mode when the question is “how fast can this workload go?”
rather than “did every verifier check run exhaustively?”:

```bash
scripts/profile-compose.sh performance
```

Default benchmark settings:

- purpose: `performance`
- workload: `read_mostly`
- target primary RPS: `100`
- concurrency: `150`
- duration: `10m`
- validation probe mode: `sampled`
- probe sampling rate: `0.10`

The YAML and Markdown reports separate primary workload throughput from total
server load:

- `throughput.primary.requestsPerSecond` excludes validation probes and is the
  number compared with the 100 RPS target.
- `throughput.validationProbes.requestsPerSecond` reports follow-up semantic
  probe traffic.
- `throughput.totalHttp.requestsPerSecond` includes primary requests, probes,
  reconciliation, and auxiliary measured HTTP traffic.

This distinction matters because probes legitimately consume server capacity,
but counting them as primary workload would overstate business throughput.

Performance mode also passes resource tuning knobs to the API container:

```bash
TREEDB_RUNTIME_CPU_BUDGET=8 \
TREEDB_RUNTIME_MEMORY_BUDGET_MB=8192 \
TREEDB_CACHE_MEMORY_FRACTION=0.35 \
TREEDB_REPOSITORY_QUERY_POOL_SIZE=16 \
TREEDB_WORKSPACE_WORKER_POOL_SIZE=16 \
TREEDB_GRAPH_WORKER_POOL_SIZE=8 \
TREEDB_REPOSITORY_QUERY_MAX_QUEUE=2000 \
TREEDB_GRAPH_MAX_QUEUE=500 \
scripts/profile-compose.sh performance
```

`TREEDB_RUNTIME_MEMORY_BUDGET_MB` and `TREEDB_CACHE_MEMORY_FRACTION` define the
cache byte budget. Repository document and graph index caches evict by TTL,
entry count, and approximate byte pressure. Worker pool sizes cap concurrent
expensive repository, workspace, graph, snapshot, and import work; bounded
queues absorb bursts behind those workers. Queue-full and queue-timeout
saturation is reported as HTTP `503` with error code `server_busy`.

Performance reports include `saturation` and `workerPools` sections. Federation
performance reports also include `federationLoadBalancing`, which shows
load-aware spillover for Git-backed repository reads to fresh trusted mirrors
when local pool pressure is high enough. The spillover probe validates
repository file reads, path listing, search, and query through a mirror. Graph,
context, snapshot, and artifact reads stay primary-served until their derived
state has an explicit replication path.

## Run A Small Profile

Start TreeDB, then run:

```bash
./scripts/profile-treedb.sh \
  --base-url http://localhost:4000 \
  --auth-mode dev \
  --fixture small-docs \
  --size small \
  --scenario full_api \
  --iterations 1 \
  --concurrency 1 \
  --fixture-root /var/lib/treedb/profiler \
  --output target/profiles/small.yaml
```

`--fixture-root` must be visible to the TreeDB server and must be under
`TREEDB_DATA_DIR`. The profiler generates Git fixtures there, then imports them
through the admin local-import API using `sourceRelativePath`; subsequent
profiling work uses public repository, workspace, graph, search, snapshot, and
artifact APIs.

Generated repositories use a common prefix. The default is `profile-`, which
creates names such as `profile-small-docs-small-1`. Override it with:

```bash
--repo-prefix test-
```

Federation profiles also keep repository storage managed. Fixture repositories
are generated under the API node's data volume for import, then registered by
canonical `repositoryName`. Reports should contain repository IDs, repository
names, relative paths, node IDs, and route metadata only, never absolute storage
paths or node authorization material.

## Fixture Families And Scale

Fixture families:

- `small-docs`: fast correctness and smoke profiling.
- `medium-mixed`: broad nested read/write/search/graph behavior.
- `binary-assets`: blob, multipart upload, download, and artifact-heavy behavior.
- `large-history`: branches, tags, commits, status, refs, and diff behavior.
- `graph-rich`: links, sections, entities, graph query, and context behavior.
- `workspace-heavy`: writes, patches, deletes, commits, snapshots, and artifacts.
- `all`: creates every fixture family.

Scale with:

```bash
--size small|medium|large|xl
```

Scale is fixture-specific. For example, `graph-rich --size medium` increases
link and section density, while `binary-assets --size medium` increases blob
counts and maximum blob sizes.

## Scenarios

Scenarios:

- `full_api`: safe public API coverage with OpenAPI route accounting.
- `read_heavy`: repository reads, search, query, graph reads, and context reads.
- `write_heavy`: workspace writes, blobs, commits, snapshots, and artifacts.
- `graph_context`: graph refresh/query, search index, and context build.
- `blob_artifact`: blob and artifact lifecycle operations.

Scenarios are workload definitions under `tools/treedb_profiler/scenarios/`.
The endpoint matrix at `tools/treedb_profiler/endpoint_matrix.yaml` determines
which public API operations are eligible for each workload, their setup
requirements, expected statuses, and validation rules.

Performance data should be interpreted only when `assertions.failed` is `0`.

## Fixed Fixtures And Portfolio Growth

Fixed fixture mode is for comparable baselines. Use the same fixture family,
size, seed, scenario, image, and concurrency when comparing hardware or TreeDB
versions.

Portfolio mode is for long-running reliability and production-shape behavior:

```bash
./scripts/profile-treedb.sh \
  --base-url http://localhost:4000 \
  --auth-mode dev \
  --load-mode portfolio \
  --duration 24h \
  --concurrency 100 \
  --portfolio-initial-repos 1 \
  --portfolio-max-repos 500 \
  --portfolio-growth-target steady \
  --report-format both \
  --output target/profiles/portfolio-24h.yaml \
  --markdown-output target/profiles/portfolio-24h.md
```

Portfolio mode starts from one or more seeded repositories, then creates new
repositories, mutates workspaces, commits changes, runs query/search/graph and
context requests, builds snapshots, exports artifacts, and closes/removes
resources where public APIs support it. Repository deletion is rare and
age-gated by default so a 24-hour run leaves a developed project portfolio.

Validation remains API-first. Shared data volumes are used only so repository
fixtures can be registered; correctness checks validate TreeDB through public
HTTP responses. Optional disk diagnostics can be enabled with:

```bash
--state-checks api_with_disk_diagnostics
```

## Comparing Hardware

Use the same TreeDB image, fixture, scenario, iteration count, and concurrency
on each machine:

```bash
./scripts/profile-treedb.sh \
  --fixture medium-mixed \
  --size medium \
  --scenario full_api \
  --iterations 100 \
  --concurrency 8 \
  --output target/profiles/medium-$(hostname).yaml
```

The report includes OS, architecture, scheduler count, memory, and Docker
availability so downstream systems can group comparable runs.

`--concurrency` sets the maximum number of measured workers active at once.
Setup is sequential and excluded from steady-state statistics. In portfolio
mode, each worker repeatedly generates one valid request from the current
runtime state, sends it, validates it, and applies the successful state effect.
`--concurrency 100` therefore runs one hundred worker loops and can produce up
to roughly one hundred simultaneous in-flight requests depending on response
times.

## Safety

For direct CLI runs, admin and destructive operations are disabled by default.
Use explicit flags only when a controlled environment is prepared:

```bash
--include-admin true
--include-destructive true
```

Do not run destructive profiles against shared production data.

## Report Contract

The canonical output format is YAML. The report includes:

- `profile`
- `target`
- `environment`
- `workload`
- `fixtures`
- `coverage`
- `metrics`
- `operations`
- `categories`
- `operationTypes`
- `portfolio`
- `errors`
- `requestSamples`
- `assertions`
- `summary`

Every OpenAPI operation is accounted for in `coverage`, even when the profiler
does not execute it by default.

## Common Runs

Fast smoke:

```bash
./scripts/profile-treedb.sh --fixture small-docs --size small --scenario full_api --iterations 1
```

Read-heavy comparison:

```bash
./scripts/profile-treedb.sh --fixture medium-mixed --size medium --scenario read_heavy --iterations 100 --concurrency 8
```

Graph/context benchmark:

```bash
./scripts/profile-treedb.sh --fixture graph-rich --size medium --scenario graph_context --iterations 50 --concurrency 4
```

Binary/artifact benchmark:

```bash
./scripts/profile-treedb.sh --fixture binary-assets --size large --scenario blob_artifact --iterations 25 --concurrency 4
```

10-minute local portfolio profile:

```bash
docker compose -f profiles/compose.profile.yaml down -v --remove-orphans
docker compose -f profiles/compose.profile.yaml -f profiles/compose.profile.portfolio.yaml up --build --abort-on-container-exit --exit-code-from treedb-profiler
```
