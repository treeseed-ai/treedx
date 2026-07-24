# TreeDX Profiler

`treedx_profiler` is a black-box API profiler for TreeDX. It creates
deterministic Git fixture repositories, registers them through the public API,
drives TreeDX operations over HTTP, validates dynamically generated
expectations, and writes YAML and optional Markdown performance reports.

The profiler does not import TreeDX server modules and does not use the SDK
package.

## Docker Compose Profile Run

The repository includes `profiles/compose.profile.yaml` for a one-command local profile.
It starts two services:

- `treedx-api`: local TreeDX API from the production release image, using dev
  auth for turnkey local profiling.
- `treedx-profiler`: profiler client that waits for API health, runs over HTTP,
  writes YAML and Markdown reports, and exits. This service uses the
  profiler image because it builds and runs the standalone escript.

Both services share `treedx-data:/var/lib/treedx`, so fixture repositories are
generated under `/var/lib/treedx/profiler` and can be registered through the
public API.

Run:

```bash
scripts/profiling/profile-compose.sh portfolio
```

The default profile runs growing portfolio mode:

- `--load-mode portfolio`
- `--fixture small-docs`
- `--size small`
- `--scenario all`
- no default iteration cap
- `--concurrency 100`
- `--duration 10m`, measured after setup completes
- `--report-format both`
- reliability verifier enabled
- admin, destructive, exec, and federation operation flags enabled

Reports are written to timestamped paths:

```text
target/profiles/portfolio-<timestamp>.yaml
target/profiles/portfolio-<timestamp>.md
target/profiles/portfolio-<timestamp>-replay.jsonl
target/profiles/portfolio-<timestamp>-failures.jsonl
```

Override profile settings with environment variables:

```bash
TREEDX_PROFILE_SIZE=medium \
TREEDX_PROFILE_CONCURRENCY=100 \
TREEDX_PROFILE_DURATION=30m \
TREEDX_PROFILE_OUTPUT=target/profiles/medium-c100.yaml \
TREEDX_PROFILE_MARKDOWN_OUTPUT=target/profiles/medium-c100.md \
scripts/profiling/profile-compose.sh portfolio
```

## Repeatable Compose Profiles

The gateway script routes named workload profiles to the base Compose manifest
plus a small override file:

```bash
scripts/profiling/profile-compose.sh smoke
scripts/profiling/profile-compose.sh fixed
scripts/profiling/profile-compose.sh portfolio
scripts/profiling/profile-compose.sh read-heavy
scripts/profiling/profile-compose.sh write-heavy
scripts/profiling/profile-compose.sh graph
scripts/profiling/profile-compose.sh binary
scripts/profiling/profile-compose.sh admin
scripts/profiling/profile-compose.sh soak
scripts/profiling/profile-compose.sh performance
```

Each profile maps to `profiles/compose.profile.<mode>.yaml` and can still be customized
with `TREEDX_PROFILE_*` variables. Use `--config` to inspect the merged Compose
configuration without running it:

```bash
scripts/profiling/profile-compose.sh graph --config
```

Use `--no-clean` to keep the previous profiling volume and `--no-build` to skip
image rebuilds. Use `--dev-api` to run the API through `mix phx.server` with the
repository bind-mounted for development profiling:

```bash
scripts/profiling/profile-compose.sh portfolio --dev-api
```

## Performance Mode And RPS

Reliability profiles remain the strict correctness gate. Performance mode is a
separate benchmark profile for RPS tuning:

```bash
scripts/profiling/profile-compose.sh performance
```

It defaults to a read-mostly portfolio workload, 150 concurrent workers, 10
minutes of measured load, sampled validation probes, and a target of 100 primary
workload requests per second. The target is reported, not enforced, unless
`--fail-below-primary-rps` or `TREEDX_PROFILE_FAIL_BELOW_PRIMARY_RPS` is set.

Reports distinguish:

- `throughput.primary.requestsPerSecond`: primary generated workload requests.
- `throughput.validationProbes.requestsPerSecond`: follow-up correctness probes.
- `throughput.totalHttp.requestsPerSecond`: primary plus probe and auxiliary
  profiler HTTP traffic during the measured window.

Validation probes are real server load, so they are included in total HTTP RPS,
but they are not counted as primary business throughput. This keeps the 100 RPS
target honest while still showing the full pressure the profiler applied.

Tune server resources for the performance profile with:

```bash
TREEDX_RUNTIME_CPU_BUDGET=8 \
TREEDX_RUNTIME_MEMORY_BUDGET_MB=8192 \
TREEDX_CACHE_MEMORY_FRACTION=0.35 \
TREEDX_REPOSITORY_QUERY_POOL_SIZE=16 \
TREEDX_WORKSPACE_WORKER_POOL_SIZE=16 \
TREEDX_REPOSITORY_QUERY_MAX_QUEUE=2000 \
scripts/profiling/profile-compose.sh performance
```

The report includes `resourceTuning`, `cache`, and `workerPools` sections when
runtime metrics are available. Pool saturation appears in the `saturation`
section as HTTP `503` `server_busy` responses grouped by operation, pool, and
reason. That is a failure in reliability mode and a capacity signal in
performance mode. Federation performance reports also include
`federationLoadBalancing` for Git-backed repository read spillover to healthy
mirrors. The federation performance spillover probe exercises repository file
reads, repository search, repository query, and path listing. Graph, context,
snapshot, and artifact reads remain primary-served unless the route is a remote
primary, because Git bundle mirror sync does not replicate those derived records
yet.

## Build

```bash
cd tools/treedx_profiler
mix deps.get
mix escript.build
```

From the repository root, use:

```bash
./scripts/profiling/profile-treedx.sh \
  --base-url http://localhost:4000 \
  --auth-mode dev \
  --fixture small-docs \
  --size small \
  --scenario full_api \
  --iterations 1 \
  --concurrency 1 \
  --fixture-root /var/lib/treedx/profiler \
  --output target/profiles/smoke.yaml
```

Use `--repo-prefix profile-` to control the common prefix used for generated
TreeDX repository names. The default prefix is `profile-`, producing names such
as `profile-small-docs-small-1`.

## Fixture Root

The profiler generates Git fixture repositories under `--fixture-root`, which
must be visible to the TreeDX server and under `TREEDX_DATA_DIR`. It then imports
those fixtures through the admin local-import API with a data-dir-relative
`sourceRelativePath`. Normal profiler setup does not send absolute repository
paths in public registration payloads.

For a containerized server this usually means creating fixtures inside the data
volume or running the profiler from an environment that shares that path with
the server.

## Load And Concurrency

`--concurrency N` is the maximum number of measured workers the
profiler runs at the same time. Setup is intentionally sequential: token
creation, fixture repository registration, workspace creation, initial
mutations, graph refresh, and snapshot setup complete before the measured load
starts.

In fixed fixture mode, each worker runs the selected scenario operation sequence
one HTTP call at a time. In portfolio mode, each worker repeatedly asks the
runtime portfolio state for one valid request, executes it, validates it, and
applies the resulting state effect. With `--concurrency 100`, one hundred
worker loops are active concurrently. Use `--duration` for sustained measured
load. When duration is provided and `--iterations` is omitted, the measured load
continues until the requested duration elapses. If both are explicitly
provided, the profiler stops when either limit is reached and the report marks
whether the requested measured duration was satisfied.

## Production Reliability Verifier

Verifier mode is enabled by default. It adds strict gates around the performance
profile:

- setup, measured-load, cleanup, and total profile timing windows
- minimum measured duration checks
- exact semantic assertions and public hygiene checks
- OpenAPI response validation for every response
- model-state reconciliation summaries
- operation-chain, negative-input, metamorphic, endpoint-consistency,
  permission-matrix, delayed-consistency, and leak-detection report sections
- causal race-interference accounting
- sanitized replay logs for request ledgers and failures

The profiler exits non-zero when the reliability budget is violated. The
default budget is `tools/treedx_profiler/reliability_budget.yaml` and requires
zero server errors, semantic failures, OpenAPI failures, reconciliation drift,
unverified races, and short measured-duration runs.

## Load Modes

`--load-mode scenario` uses the fixed scenario sequence selected by
`--scenario`.

`--load-mode random` keeps fixed fixture setup but randomizes eligible measured
requests from the endpoint matrix.

`--load-mode portfolio` starts with a small seeded repository set and grows a
project portfolio during the measured run. It can create new repositories,
create and mutate workspaces, commit changes, run search/query/graph/context
operations, build snapshots, export artifacts, and close/delete supported
resources according to enabled flags. Repository deletion is low-frequency by
default and age-gated so long runs produce a rich final portfolio.

Portfolio options:

```text
--portfolio-initial-repos 1
--portfolio-max-repos 1000
--portfolio-growth-target sparse|steady|aggressive
--portfolio-repo-prefix profile-
--portfolio-min-repo-age-before-delete 30m
```

Repository names use the configured prefix and profile ID, for example:

```text
profile-treedx-profile-20260604T120000Z-repo-000001
```

## Output

The YAML report includes:

- target health/version information
- host system profile
- fixture summary and dynamic expectations
- metrics snapshots before and after the run
- per-operation latency, standard deviation, byte, success-rate, and error-rate statistics
- assertion summary
- portfolio growth summary for portfolio mode
- optional retained request samples
- OpenAPI operation coverage accounting

The report is intended for downstream benchmark comparison systems and hardware
performance tracking.

## Canonical Fixtures

The profiler supports these fixture families:

- `small-docs`: tiny docs repository for smoke and endpoint correctness.
- `medium-mixed`: nested markdown, text, JSON, binary files, frontmatter, and links.
- `binary-assets`: deterministic binary assets across multiple sizes and content types.
- `large-history`: many commits, branches, and tags for Git/ref/status behavior.
- `graph-rich`: dense links, sections, and entities for graph/context work.
- `workspace-heavy`: write, patch, delete, commit, snapshot, and artifact workflows.
- `all`: generates every fixture family for the selected size.

Use `--size small|medium|large|xl` to scale each fixture while preserving its
shape. The default is `--fixture small-docs --size small`.

## Scenario And Endpoint Matrix

Scenarios are workload definitions under `scenarios/`. The endpoint matrix in
`endpoint_matrix.yaml` maps every OpenAPI operation to setup requirements,
tags, expected status, and a validation rule. The profiler verifies that the
matrix accounts for every operation in `docs/api/openapi.yaml`.

Every exercised operation has a correctness assertion. Routes that are not run
because they require admin access, destructive behavior, exec, federation, or
missing setup are reported explicitly in `coverage`.

## Federation Profiles

The profiler supports three-node federation profiles through the Compose gateway:

```bash
scripts/profiling/profile-compose.sh mirror-federation
scripts/profiling/profile-compose.sh connected-library
scripts/profiling/profile-compose.sh federation-soak
```

Federation profile options can also be passed directly:

```text
--federation-mode single_node|mirror_cluster|connected_library
--federation-node-a-url URL
--federation-node-b-url URL
--federation-node-c-url URL
--federation-exercise-promotion true|false
--federation-exercise-write-proxy true|false
--federation-exercise-connected-denials true|false
```

Mirror-cluster profiles verify that parent lineage converges into a trusted
catalog, remote-primary writes proxy through the ingress node, fresh mirrors can
serve reads, and mirror policy is represented in route metadata. Connected
library profiles verify that advertised remote repositories can be read or
queried through delegated scope while writes and mirror requests are denied by
default.

Federation assertions check node topology, catalog convergence, route
resolution, proxy write behavior, mirror freshness, connected-library denials,
OpenAPI response schemas, and public hygiene. Reports must not include absolute
storage paths, user tokens, node tokens, delegated tokens, hidden paths,
snippets, stdout/stderr, or binary payloads.

## Markdown Reports

Use:

```bash
--report-format both --markdown-output target/profiles/profile.md
```

The Markdown report summarizes workload configuration, portfolio growth,
coverage, category performance, per-operation latency percentiles, errors,
assertions, and retained request samples. It is intended for quick human and AI
review, while YAML remains the canonical machine-readable report.
