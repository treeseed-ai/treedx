# TreeDX SDK Spec

`@treedx/sdk-spec` is the shared architecture, capability, endpoint, test, and
conformance source for TreeDX SDKs. TypeScript, Python, Rust, and Elixir SDKs
must consume this package as the common standard for module ownership, endpoint
coverage, error behavior, pagination, binary handling, testing layout, and
conformance metadata.

## What This Is Not

This package is not generated SDK code, a language SDK, TreeSeed product
semantics, or a replacement for `docs/api/openapi.yaml`. OpenAPI remains the
TreeDX wire contract. `sdk-spec` defines how language SDKs expose and verify
that contract consistently.

## Package Roles

- `packages/sdk-spec` owns shared SDK standards and validation tooling.
- `packages/ts-sdk`, `packages/python-sdk`, `packages/rust-sdk`, and
  `packages/elixir-sdk` will implement this standard.
- `packages/trsd-sdk` is a downstream TreeSeed integration reference only. It
  may consume TreeDX SDKs later, but it does not define TreeDX SDK architecture.

## Consuming The Spec

Language SDKs should read the YAML files under `spec/`, validate their manifests
against `schemas/sdk-manifest.schema.json`, and run conformance scenarios from
`conformance/` as those scenarios are added.

## What sdk-spec Controls

`sdk-spec` controls the shared SDK contract across all TreeDX language SDKs:

- architecture modules, ports, layers, and core concepts;
- capability IDs and direct module ownership;
- endpoint strings owned by SDK capabilities;
- shared error, auth, pagination, and binary behavior;
- shared test roots and manifest status values;
- shared conformance scenario metadata;
- SDK manifest validation and capability matrix rendering.

`sdk-spec` does not own TreeSeed product models, downstream compatibility tests,
or live server deployment. Those remain outside the generic TreeDX SDK
architecture.

## Architecture Contract

`spec/architecture.yaml` is the machine-readable architecture source. It defines
canonical layer directories, required modules, required ports, core concepts,
and module-to-capability ownership. `spec/treedx-standard.md` is the
human-readable version of the same contract.

Once language SDK packages exist, each SDK manifest must report status for every
required module under `modules`.

## Capability Coverage

Capabilities are the unit of SDK completeness. Every required capability maps to
one SDK module, one or more OpenAPI endpoints, and one or more conformance
scenario IDs.

`npm run check-openapi-coverage` validates declared capability and endpoint
group references against `docs/api/openapi.yaml`. `npm run
render-capability-matrix` renders TypeScript, Python, Rust, and Elixir
implementation status from SDK manifests when they exist. Missing language SDK
manifests are reported as `not_configured`; manifest entries that omit a
capability are reported as `missing`.

OpenAPI routes not yet represented by SDK capabilities remain advisory uncovered
routes until later coverage phases.

## Shared Behavior Contracts

`spec/errors.yaml` defines `TreeDxApiError`-compatible behavior and must match
the OpenAPI `TreeDxErrorCode` enum. `spec/auth.yaml` defines bearer token, auth
provider, effective scope, and production identity behavior. `spec/pagination.yaml`
defines opaque cursor and page behavior. `spec/binary.yaml` defines binary-safe
body handling and multipart upload behavior.

`npm run validate` schema-validates these files and cross-checks them against
OpenAPI, capabilities, endpoints, and conformance scenario metadata.

## Shared Test Framework

TreeDX language SDKs share these required test roots:

- `unit`
- `adapters`
- `generated`
- `conformance`
- `integration`

Downstream consumers may add the optional `compatibility` root. Compatibility is
downstream-only and must not define TreeDX SDK architecture.

Language root mapping:

- TypeScript: `test`
- Python: `tests`
- Rust: `tests`
- Elixir: `test`

Once SDK packages exist, `npm run check-sdk-manifests` validates each manifest's
module status, test layout status, and implemented test root contents.

## Conformance Suite

Shared black-box scenario files live under `conformance/scenarios`. Every
required capability scenario id from `spec/capabilities.yaml` must be defined
exactly once. `npm run validate` verifies scenario, capability, endpoint, and
fixture consistency.

Future SDK packages will run these scenarios through conformance adapters that
exercise the public SDK facade. Generated clients and private adapters are not
the direct conformance surface.

## CI Workflows

TreeDX SDK verification is integrated into the root `TreeDX Release Gate` so
tagged service and SDK release outputs stay synchronized. `SDK Spec` runs in
parallel with service verification. Language SDK test jobs run on both `amd64`
and `arm64` after `SDK Spec` passes. On release-path pushes, Docker architecture
image builds and SDK package artifact jobs both wait for all language SDK tests
and required service profile gates, then run in parallel.

| Workflow | Scope | Required For |
| --- | --- | --- |
| TreeDX Release Gate / SDK Spec | sdk-spec validation, OpenAPI coverage, manifests, matrix, docs gate | SDK spec, OpenAPI, manifest, conformance catalog, and SDK docs changes |
| TreeDX Release Gate / TypeScript SDK Test | TypeScript generated metadata, build, tests on amd64 and arm64 | `packages/ts-sdk` changes |
| TreeDX Release Gate / Python SDK Test | Python generated metadata, build, pytest on amd64 and arm64 | `packages/python-sdk` changes |
| TreeDX Release Gate / Rust SDK Test | Rust generated metadata, fmt, clippy, tests on amd64 and arm64 | `packages/rust-sdk` changes |
| TreeDX Release Gate / Elixir SDK Test | Elixir generated metadata, format, tests on amd64 and arm64 | `packages/elixir-sdk` changes |
| TreeDX Release Gate / Publish SDK jobs | npm, Python, crate, and Hex package artifacts after service profiles and SDK tests pass; registry publish on tags | release-path pushes |

Branch and pull request runs are path-filtered. Tag pushes run release gates
without custom tag-diff filtering so release-tag verification remains reliable.
The integrated workflow builds and uploads SDK artifacts on release-path pushes.
On semantic version tag pushes, it also publishes SDK packages to npm, PyPI,
crates.io, and Hex through the GitHub `production` environment.

Equivalent local commands:

```bash
cd packages/sdk-spec
npm ci
npm run validate
npm run check-openapi-coverage
npm run check-sdk-manifests
npm run render-capability-matrix
npm test

cd packages/ts-sdk
npm ci
npm run treedx:check-generated
npm run build
npm test

cd packages/python-sdk
python -m pip install -e ".[dev]"
python scripts/check_treedx_generated_types.py
python -m build
python -m pytest

cd packages/rust-sdk
tsx scripts/check_treedx_generated_types.ts
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test

cd packages/elixir-sdk
mix deps.get
mix run scripts/check_treedx_generated_types.exs
mix format --check-formatted
mix test
```

For release-candidate SDK verification, use:

```bash
./scripts/verification/test-sdk-packages.sh
```

See `docs/runbooks/sdk-release.md` for the full SDK release process and how it
relates to the root TreeDX release gate.

## Adding A Capability

1. Add a capability entry to `spec/capabilities.yaml`.
2. Add the owned endpoint strings to `spec/endpoints.yaml`.
3. Use `METHOD /api/v1/path` endpoint strings that exactly match
   `docs/api/openapi.yaml`.
4. Add or reference conformance scenario IDs.
5. Run `npm run validate` and `npm run check-openapi-coverage`.

## Adding A Conformance Scenario

1. Add scenario metadata to `spec/conformance.yaml` or a scenario file under
   `conformance/scenarios/`.
2. Keep scenario IDs unique and tied to capability IDs.
3. Add fixtures under `conformance/fixtures/requests` and
   `conformance/fixtures/expected` when the scenario needs request/response
   examples.
4. Run `npm run validate`.

## Adding A Language SDK

1. Create the package under the language target path from `spec/testing.yaml`.
2. Add `sdk-manifest.yaml` with `language`, `sdkSpecVersion`, `openapiVersion`,
   every required module, every required capability, and every required test
   root.
3. Follow the language root layout from `testing.yaml`.
4. Implement every required module from `spec/architecture.yaml`.
5. Add generated-like OpenAPI operation metadata derived from
   `docs/api/openapi.yaml`.
6. Add a conformance adapter that loads Phase 7 scenario records and reports
   clean `not_configured` behavior until live dispatch exists.
7. Run `npm run check-sdk-manifests` and `npm run render-capability-matrix`.

## Updating OpenAPI Coverage

1. Update `docs/api/openapi.yaml`; it remains the wire contract.
2. Update `spec/endpoints.yaml` only for public SDK-owned capability endpoints.
3. Update `spec/capabilities.yaml` so each SDK endpoint is owned by exactly one
   capability unless explicitly allowlisted as shared.
4. Regenerate or check generated-like metadata in each language SDK.
5. Run `npm run validate` and `npm run check-openapi-coverage`.

## Rendering The Capability Matrix

Run:

```bash
npm run render-capability-matrix
```

The matrix reads SDK manifests and prints one status column per language.
`partial` means the SDK reports partial support, `missing` means a manifest
exists but omits a required capability, and `not_configured` means no manifest
exists for that language.

## Validation

```bash
npm install
npm run validate
npm run check-openapi-coverage
npm run check-sdk-manifests
npm run render-capability-matrix
npm test
```

Run the documentation gate from the repository root after SDK doc changes:

```bash
./scripts/verification/check-sdk-docs.sh
```

## Phase 2 Limits

Conformance fixtures are placeholders in Phase 2. OpenAPI routes that are not
yet represented by SDK capabilities are reported as advisory uncovered routes
until later phases make coverage exhaustive.
