# Performance Profiler

The TreeDB profiler is a standalone Elixir escript located at
`tools/treedb_profiler`.

## Design

The profiler is intentionally black-box:

- It talks to TreeDB only through HTTP.
- It does not import `apps/api` modules.
- It does not use the SDK package.
- It creates Git repositories only as source fixtures for
  `POST /api/v1/repos/register`.

After registration, all TreeDB state is created, updated, queried, and cleaned
up through public API calls.

## Dynamic Expectations

Fixture generation produces an expectation manifest for each run. The profiler
uses that manifest to validate repository counts, generated files, search hits,
workspace mutations, graph/context behavior, blobs, snapshots, and artifacts.

Performance numbers are trusted only when assertions pass.

## Canonical Fixtures

Fixed fixture mode uses canonical benchmark fixture families rather than ad hoc
file sets:

- `small-docs`
- `medium-mixed`
- `binary-assets`
- `large-history`
- `graph-rich`
- `workspace-heavy`

Each fixture supports `--size small|medium|large|xl`. Scaling is
fixture-specific so the workload shape remains meaningful: history fixtures
increase commits and refs, graph fixtures increase links and sections, and
binary fixtures increase blob counts and sizes.

Generated contents are deterministic from fixture ID, size, profile ID, repo
index, file index, commit index, and seed. The expectation manifest records
paths, search hits, graph lower bounds, workspace mutation targets, and content
hash metadata.

## Portfolio Growth

Portfolio mode starts from a small seeded repository set and grows the managed
project portfolio while the measured run is active. It is intended for
production-shape soak testing rather than exact run-to-run comparison.

A portfolio run can create repositories, create and mutate workspaces, commit
changes, run graph/search/context workloads, build snapshots, export artifacts,
and close or delete supported resources. Repository deletion is rare and
age-gated by default so long runs leave a useful final corpus for inspection.

Portfolio state is held by a profiler-owned GenServer. It tracks generated and
registered repositories, active and closed workspaces, known readable paths,
binary paths and hashes, snapshots, artifacts, counters, and deletion
eligibility. This state is only profiler metadata; TreeDB state is still
created and verified through public HTTP APIs.

## Measurement

Each HTTP call records:

- operation ID
- method
- path template
- scenario
- fixture
- status
- duration in milliseconds using monotonic time
- request and response byte counts
- error code
- assertion result

The report aggregates min, mean, standard deviation, p50, p75, p90, p95, p99,
max, status counts, error counts, success rates, byte counts, and assertion
counts by operation.

Measured load is applied with bounded workers. `--concurrency N` starts up to
`N` concurrent workers during the measured phase. In fixed fixture mode, each
worker executes the selected workload sequence one HTTP request at a time. In
portfolio mode, each worker asks the runtime portfolio state for one valid
request, executes it, validates the response, and applies the successful state
effect before asking for the next request. Setup work such as repo registration,
workspace creation, graph refresh, and snapshot preparation remains sequential
and is not mixed into steady-state operation statistics.

## OpenAPI Coverage

The profiler reads `docs/api/openapi.json` and verifies
`tools/treedb_profiler/endpoint_matrix.yaml` accounts for every public
operation. The endpoint matrix adds setup state, request templates, tags,
expected statuses, scenario weights, and validation rules that OpenAPI cannot
derive by itself.

Routes not executed by the selected scenario are reported with explicit status,
such as admin-disabled, destructive-disabled, exec-disabled,
federation-disabled, optional-unavailable, or not-selected-by-scenario.

The report must keep `coverage.unaccounted` at `0`.

## Workloads

Scenario definitions under `tools/treedb_profiler/scenarios/` select matrix
operations by tags and weights. This keeps profiles workload-driven:

- `full_api`
- `read_heavy`
- `write_heavy`
- `graph_context`
- `blob_artifact`

Every exercised operation has a validation rule. Assertion failures are written
to the YAML report and cause a non-zero profiler exit.

## Reports

YAML is the canonical machine-readable report. Markdown is available with:

```bash
--report-format markdown
--report-format both
```

Markdown reports include summary statistics, workload configuration, portfolio
growth, endpoint coverage, category performance, per-operation latency tables,
slowest operations, errors, assertions, metrics deltas, and retained request
sample counts.
