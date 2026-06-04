# TreeDB Profiler

`treedb_profiler` is a black-box API profiler for TreeDB. It creates
deterministic Git fixture repositories, registers them through the public API,
drives TreeDB operations over HTTP, validates dynamically generated
expectations, and writes YAML and optional Markdown performance reports.

The profiler does not import TreeDB server modules and does not use the SDK
package.

## Docker Compose Profile Run

The repository includes `profiles/compose.profile.yaml` for a one-command local profile.
It starts two services:

- `treedb-api`: local TreeDB API from the production release image, using dev
  auth for turnkey local profiling.
- `treedb-profiler`: profiler client that waits for API health, runs over HTTP,
  writes YAML and Markdown reports, and exits. This service uses the
  development image because it builds and runs the standalone escript.

Both services share `treedb-data:/var/lib/treedb`, so fixture repositories are
generated under `/var/lib/treedb/profiler` and can be registered through the
public API.

Run:

```bash
scripts/profile-compose.sh portfolio
```

The default profile runs growing portfolio mode:

- `--load-mode portfolio`
- `--fixture small-docs`
- `--size small`
- `--scenario all`
- `--iterations 100000`
- `--concurrency 100`
- `--duration 10m`
- `--report-format both`
- admin, destructive, exec, and federation operation flags enabled

Reports are written to timestamped paths:

```text
target/profiles/portfolio-<timestamp>.yaml
target/profiles/portfolio-<timestamp>.md
```

Override profile settings with environment variables:

```bash
TREEDB_PROFILE_SIZE=medium \
TREEDB_PROFILE_ITERATIONS=500 \
TREEDB_PROFILE_CONCURRENCY=100 \
TREEDB_PROFILE_DURATION=30m \
TREEDB_PROFILE_OUTPUT=target/profiles/medium-c100.yaml \
TREEDB_PROFILE_MARKDOWN_OUTPUT=target/profiles/medium-c100.md \
scripts/profile-compose.sh portfolio
```

## Repeatable Compose Profiles

The gateway script routes named workload profiles to the base Compose manifest
plus a small override file:

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
```

Each profile maps to `profiles/compose.profile.<mode>.yaml` and can still be customized
with `TREEDB_PROFILE_*` variables. Use `--config` to inspect the merged Compose
configuration without running it:

```bash
scripts/profile-compose.sh graph --config
```

Use `--no-clean` to keep the previous profiling volume and `--no-build` to skip
image rebuilds. Use `--dev-api` to run the API through `mix phx.server` with the
repository bind-mounted for development profiling:

```bash
scripts/profile-compose.sh portfolio --dev-api
```

## Build

```bash
cd tools/treedb_profiler
mix deps.get
mix escript.build
```

From the repository root, use:

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
  --output target/profiles/smoke.yaml
```

Use `--repo-prefix profile-` to control the common prefix used for generated
TreeDB repository names. The default prefix is `profile-`, producing names such
as `profile-small-docs-small-1`.

## Fixture Root

TreeDB repository registration requires `localPath` to be under
`TREEDB_DATA_DIR`. Set `--fixture-root` to a directory that the TreeDB server can
read and that is under its configured data directory.

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
worker loops are active concurrently. Use `--iterations` to set an upper bound
on generated requests and `--duration` to stop after a wall-clock budget. If
both are provided, the profiler stops when either limit is reached. The Compose
profile sets a high iteration bound so the 10 minute duration controls the
default local run.

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
profile-treedb-profile-20260604T120000Z-repo-000001
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
matrix accounts for every operation in `docs/api/openapi.json`.

Every exercised operation has a correctness assertion. Routes that are not run
because they require admin access, destructive behavior, exec, federation, or
missing setup are reported explicitly in `coverage`.

## Markdown Reports

Use:

```bash
--report-format both --markdown-output target/profiles/profile.md
```

The Markdown report summarizes workload configuration, portfolio growth,
coverage, category performance, per-operation latency percentiles, errors,
assertions, and retained request samples. It is intended for quick human and AI
review, while YAML remains the canonical machine-readable report.
