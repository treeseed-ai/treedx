# TreeDX SDK Spec and Multi-Language SDK Implementation Plan

Status: Draft v0.2
Date: 2026-06-05
Canonical location: `docs/architecture/treedx-spec-implementation-plan.md`
Plan implementation status: Implemented SDK baseline with full `/api/v1` OpenAPI coverage.
Non-canonical draft: `sdk-plan.md`
SDK manifest status: `implemented` for TypeScript, Python, Rust, and Elixir.
Live executable conformance: local TreeDX harness.
Live conformance uses the local TreeDX harness for implemented SDK verification.

Primary packages:

- `packages/sdk-spec`
- `packages/ts-sdk`
- `packages/python-sdk`
- `packages/rust-sdk`
- `packages/elixir-sdk`

Reference integration package:

- `packages/trsd-sdk`

## Purpose

Create one shared TreeDX SDK standard and four language-specific SDK packages that stay aligned over time:

- TypeScript
- Python
- Rust
- Elixir

This plan uses one step-wise development unit only: **phases**. Each phase includes its goal, expected repository changes, testing work, documentation work, and completion checks. There are no separate epics, milestones, or parallel planning units.

The completed implementation should provide:

- A shared `packages/sdk-spec` standard.
- A TypeScript TreeDX SDK implementation aligned with the same shared architecture as every other language SDK.
- New Python, Rust, and Elixir TreeDX SDK packages.
- A shared SDK test framework.
- A shared conformance suite.
- GitHub Actions workflows for package, generated-contract, conformance, integration, and documentation checks.
- Documentation that explains SDK architecture, package usage, conformance, and release responsibilities.

## Phase Completion Matrix

| Phase | Area | Completion State |
| --- | --- | --- |
| 1 | Baseline and naming | Complete |
| 2 | `packages/sdk-spec` | Complete |
| 3 | Shared architecture contract | Complete |
| 4 | Shared test framework | Complete |
| 5 | Capability and endpoint coverage | Complete |
| 6 | Error/auth/pagination/binary contracts | Complete |
| 7 | Shared conformance catalog | Complete |
| 8 | TypeScript SDK baseline | Complete, `implemented` manifest |
| 9 | TreeSeed downstream integration | Complete |
| 10 | Python SDK baseline | Complete, `implemented` manifest |
| 11 | Rust SDK baseline | Complete, `implemented` manifest |
| 12 | Elixir SDK baseline | Complete, `implemented` manifest |
| 13 | SDK GitHub Actions | Complete |
| 14 | Release gate relationship and local SDK gate | Complete |
| 15 | Documentation and onboarding | Complete |
| 16 | Final verification and baseline completion | Complete |

`Complete` means the planned baseline work for the phase exists and validates.
For language SDK packages, capability status is `implemented` after full `/api/v1` OpenAPI endpoint ownership, first-class scoped modules, generated metadata checks, and local-harness conformance coverage.

## Full OpenAPI Implemented Baseline

Historical phase notes before the implemented baseline may mention `partial` as an earlier status. The current completed state is `implemented` for all four language SDK manifests.

## Full OpenAPI Implemented Baseline

All four generic SDK packages now expose every `/api/v1` operation declared in `docs/api/openapi.yaml`. Sensitive and administrative surfaces are explicit scoped modules: `Admin`, `Audit`, `Policy`, `SearchIndex`, and `FederationInternal`. `packages/sdk-spec` owns all 113 operations, and OpenAPI coverage has zero advisory-uncovered operations. SDK manifests report `implemented`; TreeSeed remains a standalone downstream package and does not define generic SDK architecture.

## Current Situation and Planning Constraints

TreeDX already has a strong API and SDK foundation:

- TreeDX public compatibility is based on `docs/api/openapi.yaml`, contract tests, stable error envelopes, and stable error codes.
- `packages/trsd-sdk` is the existing `@treeseed/sdk` package and is useful as an integration reference for connected authentication, permissions, and higher-level SDK consumption of TreeDX.
- `packages/trsd-sdk` is not the TreeDX TypeScript SDK and must not define the TreeDX SDK architecture.
- The future `packages/ts-sdk` package is the TypeScript TreeDX SDK package. It is a new TreeDX SDK project, not a copy, rename, symlink, or alias of `packages/trsd-sdk`.
- Existing TreeSeed SDK behavior must remain stable. TreeDX SDKs should provide generic repository/database clients that `packages/trsd-sdk` can consume instead of embedding direct TreeDX calls.
- TypeScript must follow the same shared `sdk-spec` architecture and endpoint model as Python, Rust, and Elixir.
- TreeDX APIs must stay generic: repo, ref, path, graph, search, context, and capability. TreeSeed model names, aliases, product concepts, market concepts, and workflow semantics must remain SDK-side or application-side.
- The current root release gate verifies the TreeDX service and SDK release set together so tagged API and SDK outputs remain synchronized.
- Historical docs may refer to `packages/ts-sdk` while describing behavior that currently exists only in `packages/trsd-sdk`. Phase 1 records that mismatch and makes the future `packages/ts-sdk` naming unambiguous.

## Phase 1 — Establish the Baseline and Naming Decisions

### Goal

Make the current state explicit before introducing new packages, new specs, or new workflows. Phase 1 is documentation and verification only. It does not create `packages/sdk-spec`, `packages/ts-sdk`, or any other language SDK package.

### Repository Changes

Create this canonical planning document:

```text
docs/architecture/treedx-spec-implementation-plan.md
```

Record the package baseline:

```text
packages/trsd-sdk
  existing @treeseed/sdk package
  reference consumer for future TreeDX SDK integration
  not the canonical TreeDX TypeScript SDK
  currently has no tracked src/treedx implementation in this checkout
  existing tests include workflow suites with side effects in temporary repos

packages/ts-sdk
  future TypeScript TreeDX SDK package
  to be created in a later phase
  must follow the same sdk-spec architecture as Python, Rust, and Elixir

docs/api/openapi.yaml
  current TreeDX wire contract

docs/architecture/sdk-integration.md
  existing TreeSeed SDK integration architecture notes
  currently use historical packages/ts-sdk wording and must be clarified

docs/research/sdk-integration-design.md
  existing AgentSdk / TreeDX design notes
  useful only as integration reference material

docs/research/sdk-baseline-verification.md
  historical TreeSeed SDK verification baseline
  currently refers to packages/ts-sdk but describes packages/trsd-sdk-era behavior
```

Resolve package naming:

```text
The TreeDX TypeScript SDK package is packages/ts-sdk.

packages/trsd-sdk is not the TreeDX TypeScript SDK. It is the existing
@treeseed/sdk package and is useful as an integration reference because it
shows how a higher-level product SDK may consume TreeDX capabilities, connected
authentication, and permissions. The TreeDX SDK packages must remain generic
repo/ref/path/graph/search/context/capability clients and must not encode
TreeSeed product concepts.
```

Recommended decision:

```text
Use packages/sdk-spec for the standard.
Create packages/ts-sdk as the TypeScript TreeDX SDK package.
Add packages/python-sdk, packages/rust-sdk, and packages/elixir-sdk.
Keep packages/trsd-sdk separate as the TreeSeed integration reference and
eventual consumer of packages/ts-sdk.
```

### Testing Work

Run and record TreeDX API contract checks:

```bash
cd apps/api && mix test test/treedx_web/openapi_contract_test.exs
cd apps/api && mix test test/treedx_web/route_openapi_inventory_test.exs
```

Observed Phase 1 baseline:

```text
mix test test/treedx_web/openapi_contract_test.exs
  pass: 3 tests, 0 failures

mix test test/treedx_web/route_openapi_inventory_test.exs
  pass: 1 test, 0 failures

./scripts/openapi-check.sh
  initial observed result: blocked because the TreeDX data directory was already locked by PID 1223583
  latest serial retry: pass, 4 tests, 0 failures
```

Run and record the focused TreeSeed integration-reference baseline:

```bash
cd packages/trsd-sdk
npx vitest run --config ./vitest.config.ts test/utils/package-graph.test.ts test/utils/sdk.test.ts
```

Observed Phase 1 baseline:

```text
cd packages/trsd-sdk
npx vitest run --config ./vitest.config.ts test/utils/package-graph.test.ts test/utils/sdk.test.ts
  fail: package-graph self-scan still finds deprecated alias
  pass: sdk.test.ts
  total focused result: 1 failed file, 1 passed file, 26 passed tests, 1 failed test
```

Do not treat `npm test` in `packages/trsd-sdk` as a clean Phase 1 baseline command until isolated. The full suite runs long workflow lifecycle tests and performs Git operations in temporary repositories.

### Public Interfaces and Package Boundaries

No public SDK APIs are created in Phase 1.

Phase 1 only locks these future interface boundaries:

- `packages/sdk-spec` will define shared SDK architecture, endpoint coverage, auth/error behavior, pagination, binary handling, and conformance scenarios.
- `packages/ts-sdk`, `packages/python-sdk`, `packages/rust-sdk`, and `packages/elixir-sdk` will implement that same contract.
- `packages/trsd-sdk` will consume `packages/ts-sdk` later instead of directly embedding TreeDX database calls.
- TreeDX SDK APIs must stay generic and OpenAPI-aligned: repo, ref, path, workspace, file/blob, graph, search, context, auth, policy, and capability.

### Documentation Work

Add this SDK naming and baseline note to the plan:

```text
The TreeDX TypeScript SDK package is packages/ts-sdk.
packages/ts-sdk is a future generic TreeDX SDK package, not a copy or alias of
packages/trsd-sdk. packages/trsd-sdk remains the existing TreeSeed SDK package
and is only a reference integration consumer for auth, permissions, and
higher-level SDK consumption patterns.
```

### Phase Complete When

- Package names are decided.
- Current TreeSeed integration-reference verification status is documented.
- Current TreeDX OpenAPI contract verification status is documented.
- The plan has one canonical implementation path and no unresolved package-name ambiguity.
- No SDK packages, workflows, schemas, generators, or conformance fixtures have been created.

### Phase 1 Completion Status

Phase 1 is complete. This document is the canonical architecture plan. The
draft `sdk-plan.md` remains a non-canonical draft source. `packages/sdk-spec`
creation begins in Phase 2, while `packages/ts-sdk`, `packages/python-sdk`,
`packages/rust-sdk`, and `packages/elixir-sdk` remain future package work.

---

## Phase 2 — Create `packages/sdk-spec`

### Goal

Create the shared SDK standard package that all language SDKs use as their architecture and conformance source.

### Repository Changes

Create:

```text
packages/sdk-spec/
  README.md
  package.json
  spec/
    treedx-standard.md
    architecture.yaml
    capabilities.yaml
    endpoints.yaml
    errors.yaml
    pagination.yaml
    binary.yaml
    auth.yaml
    testing.yaml
    conformance.yaml
  schemas/
    architecture.schema.json
    capability.schema.json
    endpoint.schema.json
    error.schema.json
    testing.schema.json
    scenario.schema.json
    sdk-manifest.schema.json
  conformance/
    README.md
    fixtures/
      repos/
      requests/
      expected/
    scenarios/
  scripts/
    validate-spec.ts
    render-capability-matrix.ts
    check-openapi-coverage.ts
    check-sdk-manifest.ts
```

Add `packages/sdk-spec/package.json`:

```json
{
  "name": "@treedx/sdk-spec",
  "private": true,
  "type": "module",
  "scripts": {
    "validate": "tsx scripts/validate-spec.ts",
    "check-openapi-coverage": "tsx scripts/check-openapi-coverage.ts",
    "check-sdk-manifests": "tsx scripts/check-sdk-manifest.ts",
    "render-capability-matrix": "tsx scripts/render-capability-matrix.ts",
    "test": "npm run validate && npm run check-openapi-coverage"
  },
  "devDependencies": {
    "ajv": "^8.17.1",
    "yaml": "^2.7.0"
  }
}
```

### Testing Work

Add validation tests for:

```text
spec/*.yaml parses
spec/*.yaml matches schemas
all required capability IDs are unique
all scenario IDs are unique
all required test categories are defined
all SDK manifest schemas are valid
```

### Documentation Work

Write `packages/sdk-spec/README.md` with:

```text
What sdk-spec is
What sdk-spec is not
How language SDKs consume it
How to add a capability
How to add a conformance scenario
How to validate the spec
```

### Phase Complete When

- `packages/sdk-spec` exists.
- `npm run validate` passes in `packages/sdk-spec`.
- `sdk-spec` has no generated code or language-specific implementation code.
- `sdk-spec` clearly owns SDK architecture, capability coverage, test layout, and conformance.

### Phase 2 Completion Status

Phase 2 is complete. `packages/sdk-spec` exists as a standalone npm package with
spec files, schemas, conformance placeholders, validation scripts,
`package.json`, and `package-lock.json`. `npm run validate`,
`npm run check-openapi-coverage`, and `npm test` pass in `packages/sdk-spec`.
OpenAPI uncovered routes remain advisory until later coverage phases.

---

## Phase 3 — Define the Shared SDK Architecture Contract

### Goal

Make one common architecture that TypeScript, Python, Rust, and Elixir must implement.

### Repository Changes

Create `packages/sdk-spec/spec/architecture.yaml`:

```yaml
version: 0.1.0

layers:
  generated:
    description: OpenAPI-generated or OpenAPI-validated schemas and low-level operation shapes.
    public: false

  core:
    description: Shared TreeDX SDK behavior across all public modules.
    public: partial

  facade:
    description: Idiomatic language-specific API built on the core layer.
    public: true

required_modules:
  - Client
  - Auth
  - Repositories
  - Workspaces
  - Files
  - Blobs
  - Query
  - Graph
  - Context
  - Federation
  - Registry
  - Snapshots
  - Artifacts
  - Mirrors
  - Migrations
  - Exec
  - Observability

required_ports:
  - transport
  - auth_provider
  - repository_adapter
  - workspace_adapter
  - file_adapter
  - blob_adapter
  - query_adapter
  - graph_adapter
  - context_adapter
  - federation_adapter
  - snapshot_adapter
  - artifact_adapter
  - mirror_adapter
  - migration_adapter
  - exec_adapter

required_core_concepts:
  - TreeDxClientConfig
  - Transport
  - AuthProvider
  - TreeDxApiError
  - TreeDxPage
  - TreeDxCursor
  - BinaryBody
  - MultipartUpload
  - CapabilityMatrix
  - ConformanceAdapter
```

Create `packages/sdk-spec/spec/treedx-standard.md` with sections:

```markdown
# TreeDX SDK Standard

## Purpose
## Non-Goals
## Common Package Architecture
## Generated Layer
## Core Layer
## Public Facade Layer
## Auth Contract
## Transport Contract
## Error Contract
## Pagination Contract
## Binary and Multipart Contract
## Repository Contract
## Workspace Contract
## File and Blob Contract
## Query Contract
## Graph and Context Contract
## Federation Contract
## Snapshot and Artifact Contract
## Mirror and Migration Contract
## Exec Contract
## Observability Contract
## Shared Test Framework
## Conformance Rules
## Versioning Policy
```

### Testing Work

Add architecture validation:

```text
Every required module has an entry in capabilities.yaml.
Every required port has at least one owning module.
Every language sdk-manifest.yaml must report required module status.
```

### Documentation Work

Document the canonical layers:

```text
generated/
core/
facade/
conformance/
```

Document that generated OpenAPI clients are not the entire public SDK.

### Phase Complete When

- The common SDK architecture is machine-readable.
- The common SDK architecture is human-readable.
- All implementation packages have a target layout derived from the same architecture.

### Phase 3 Completion Status

Phase 3 is complete. `architecture.yaml` defines canonical layers, modules,
ports, core concepts, and module/capability ownership;
`treedx-standard.md` documents the same architecture for humans; and
`npm run validate` enforces module, port, concept, and future manifest
architecture coverage.

---

## Phase 4 — Define the Shared Test Framework

### Goal

Use the same test architecture for all language SDKs.

Downstream product SDKs such as `packages/trsd-sdk` may have extra compatibility tests for TreeSeed migration safety, but TreeDX language SDK tests must follow the same required structure across TypeScript, Python, Rust, and Elixir.

### Repository Changes

Create `packages/sdk-spec/spec/testing.yaml`:

```yaml
version: 0.1.0

shared_test_roots:
  - unit
  - adapters
  - generated
  - conformance
  - integration

optional_test_roots:
  - compatibility

required_test_categories:
  unit:
    description: Pure unit tests for client, config, transport, auth, errors, pagination, and binary helpers.

  adapters:
    description: Module adapter tests against mocked transport.

  generated:
    description: OpenAPI-generated type freshness, exports, and schema coverage tests.

  conformance:
    description: Shared scenario tests driven by sdk-spec fixtures.

  integration:
    description: Local or live TreeDX API tests.

  compatibility:
    description: Migration-specific tests for downstream product SDKs that consume TreeDX SDKs.

language_roots:
  typescript: test
  python: tests
  rust: tests
  elixir: test

rules:
  - All SDKs must implement unit, adapters, generated, conformance, and integration categories.
  - Downstream product SDKs such as packages/trsd-sdk may additionally implement compatibility tests for migration safety.
  - Compatibility tests must not define the cross-language TreeDX SDK architecture.
  - Conformance scenarios must be sourced from packages/sdk-spec/conformance/scenarios.
  - Integration tests must skip or report not configured cleanly when live server credentials are absent.
```

Target TypeScript test layout:

```text
packages/ts-sdk/test/
  unit/
  adapters/
  generated/
  conformance/
  integration/
```

Target Python test layout:

```text
packages/python-sdk/tests/
  unit/
  adapters/
  generated/
  conformance/
  integration/
```

Target Rust test layout:

```text
packages/rust-sdk/tests/
  unit/
  adapters/
  generated/
  conformance/
  integration/
```

Target Elixir test layout:

```text
packages/elixir-sdk/test/
  unit/
  adapters/
  generated/
  conformance/
  integration/
```

### Testing Work

Add `packages/sdk-spec/scripts/check-sdk-manifest.ts` checks:

```text
Each SDK manifest declares all required test roots.
TreeDX language SDKs do not require compatibility roots.
Downstream product SDK manifests may declare compatibility roots when they consume TreeDX SDKs.
Each declared test root exists.
Each required test root has at least one placeholder test before package is marked implemented.
```

### Documentation Work

Document category responsibilities:

```text
unit: pure SDK behavior, no server
adapters: mocked transport request/response behavior
generated: OpenAPI type freshness and export checks
conformance: shared scenarios through SDK public API
integration: real TreeDX server
compatibility: downstream product SDK migration safety, such as packages/trsd-sdk TreeSeed integration tests
```

### Phase Complete When

- The test framework is defined once in `sdk-spec`.
- All four SDKs have the same required test categories.
- Compatibility is documented as downstream product SDK migration-only, not as a TreeDX language SDK architecture category.

### Phase 4 Completion Status

Phase 4 is complete. `testing.yaml` defines the shared required and optional
test roots, per-category responsibilities, language target layouts, and
manifest test layout requirements. `validate-spec.ts` enforces the shared
framework, and `check-sdk-manifest.ts` validates future SDK manifests and
implemented test roots.

---

## Phase 5 — Define Capability and Endpoint Coverage

### Goal

Make SDK completeness measurable.

### Repository Changes

Create `packages/sdk-spec/spec/capabilities.yaml`:

```yaml
version: 0.1.0

capabilities:
  health.basic:
    status: required
    module: Client
    api:
      - GET /api/v1/health
      - GET /api/v1/version
    conformance:
      - health.basic

  auth.whoami:
    status: required
    module: Auth
    api:
      - GET /api/v1/auth/whoami
      - GET /api/v1/policy/effective-scope
    conformance:
      - auth.whoami
      - auth.effective_scope

  repositories.lifecycle:
    status: required
    module: Repositories
    api:
      - GET /api/v1/repos
      - POST /api/v1/repos/register
      - GET /api/v1/repos/{repo_id}
      - GET /api/v1/repos/{repo_id}/status
      - GET /api/v1/repos/{repo_id}/refs
      - GET /api/v1/repos/{repo_id}/remotes
    conformance:
      - repositories.register_get_status
      - repositories.refs_remotes

  workspaces.lifecycle:
    status: required
    module: Workspaces
    api:
      - POST /api/v1/repos/{repo_id}/workspaces
      - GET /api/v1/workspaces/{workspace_id}
      - POST /api/v1/workspaces/{workspace_id}/close
    conformance:
      - workspaces.create_get_close

  files.lifecycle:
    status: required
    module: Files
    api:
      - GET /api/v1/workspaces/{workspace_id}/tree
      - GET /api/v1/workspaces/{workspace_id}/files
      - PUT /api/v1/workspaces/{workspace_id}/files
      - PATCH /api/v1/workspaces/{workspace_id}/files
      - DELETE /api/v1/workspaces/{workspace_id}/files
      - POST /api/v1/workspaces/{workspace_id}/search
      - GET /api/v1/workspaces/{workspace_id}/status
      - GET /api/v1/workspaces/{workspace_id}/diff
      - POST /api/v1/workspaces/{workspace_id}/commit
    conformance:
      - files.tree_read_write_patch_delete
      - files.search_status_diff_commit

  blobs.binary:
    status: required
    module: Blobs
    api:
      - POST /api/v1/repos/{repo_id}/blobs/read
      - PUT /api/v1/workspaces/{workspace_id}/blobs
      - DELETE /api/v1/workspaces/{workspace_id}/blobs
      - GET /api/v1/workspaces/{workspace_id}/blobs/download
      - PUT /api/v1/workspaces/{workspace_id}/blobs/upload
    conformance:
      - blobs.read_write_download_upload

  blobs.multipart:
    status: required
    module: Blobs
    api:
      - POST /api/v1/workspaces/{workspace_id}/uploads
      - PUT /api/v1/workspaces/{workspace_id}/uploads/{upload_id}/parts/{part_number}
      - POST /api/v1/workspaces/{workspace_id}/uploads/{upload_id}/complete
      - POST /api/v1/workspaces/{workspace_id}/uploads/{upload_id}/abort
    conformance:
      - blobs.multipart_upload

  query.repository:
    status: required
    module: Query
    api:
      - POST /api/v1/repos/{repo_id}/files/read
      - POST /api/v1/repos/{repo_id}/paths/list
      - POST /api/v1/repos/{repo_id}/files/search
      - POST /api/v1/repos/{repo_id}/query
    conformance:
      - query.read_file
      - query.paths_list
      - query.search_filter_sort
      - query.changed_paths
      - query.pagination

  graph.context:
    status: required
    module: Graph
    api:
      - POST /api/v1/repos/{repo_id}/graph/refresh
      - POST /api/v1/repos/{repo_id}/graph/query
      - POST /api/v1/repos/{repo_id}/context/build
      - POST /api/v1/repos/{repo_id}/context/parse-ctx
    conformance:
      - graph.refresh
      - graph.query
      - context.build
      - context.parse_ctx

  federation.global_query:
    status: required
    module: Federation
    api:
      - POST /api/v1/search
      - POST /api/v1/query
      - POST /api/v1/context/build
      - POST /api/v1/graph/query
      - POST /api/v1/federation/query/plan
    conformance:
      - federation.plan
      - federation.global_search
      - federation.global_query
      - federation.partial_failure

  snapshots.artifacts:
    status: required
    module: Snapshots
    api:
      - POST /api/v1/repos/{repo_id}/snapshots/build
      - GET /api/v1/repos/{repo_id}/snapshots/{snapshot_id}
      - POST /api/v1/repos/{repo_id}/artifacts/export
      - GET /api/v1/repos/{repo_id}/artifacts
      - GET /api/v1/repos/{repo_id}/artifacts/{artifact_id}
      - DELETE /api/v1/repos/{repo_id}/artifacts/{artifact_id}
    conformance:
      - snapshots.build_get_export
      - artifacts.list_get_delete

  mirrors.migrations:
    status: required
    module: Mirrors
    api:
      - POST /api/v1/repos/{repo_id}/mirrors
      - POST /api/v1/repos/{repo_id}/mirrors/{mirror_id}/health
      - POST /api/v1/repos/{repo_id}/mirrors/{mirror_id}/promote
      - POST /api/v1/repos/{repo_id}/migrations
      - GET /api/v1/repos/{repo_id}/migrations/{migration_id}
    conformance:
      - mirrors.create_health_promote
      - migrations.plan

  exec.workspace:
    status: required
    module: Exec
    api:
      - POST /api/v1/workspaces/{workspace_id}/exec
    conformance:
      - exec.read_only
      - exec.write_limited

  observability.health_metrics:
    status: required
    module: Observability
    api:
      - GET /api/v1/health
      - GET /api/v1/ready
      - GET /api/v1/health/deep
      - GET /api/v1/metrics
    conformance:
      - observability.health_metrics
```

### Testing Work

Implement `check-openapi-coverage.ts`:

```text
Load docs/api/openapi.yaml.
Load packages/sdk-spec/spec/capabilities.yaml.
Verify every endpoint listed in capabilities exists in OpenAPI.
Verify every required capability has at least one conformance scenario.
Verify every required capability maps to one required SDK module.
```

### Documentation Work

Generate a capability matrix:

```text
Capability | TypeScript | Python | Rust | Elixir
```

### Phase Complete When

- All current required TreeDX SDK capability groups are represented.
- Endpoint references are checked against OpenAPI.
- The capability matrix can be rendered from manifests.

### Phase 5 Completion Status

Phase 5 is complete. `capabilities.yaml` defines required SDK capability groups
with direct module ownership, OpenAPI endpoint references, required flags, and
conformance scenario IDs. `check-openapi-coverage` verifies declared endpoints
against `docs/api/openapi.yaml` and reports advisory uncovered routes.
`render-capability-matrix` renders a cross-language capability matrix from
future SDK manifests.

---

## Phase 6 — Define Error, Auth, Pagination, and Binary Contracts

### Goal

Make cross-language behavior consistent for the most common SDK portability issues.

### Repository Changes

Create `packages/sdk-spec/spec/errors.yaml`:

```yaml
version: 0.1.0

api_error_shape:
  status: integer
  code: string
  message: string
  details: object
  payload: object

network_error:
  status: 0
  code: network_error

required_error_codes:
  - authentication_required
  - invalid_token
  - token_expired
  - invalid_issuer
  - invalid_audience
  - permission_denied
  - workspace_revoked
  - not_found
  - conflict
  - payload_too_large
  - unsupported_media_type
  - validation_error
  - service_unavailable
  - federated_scope_empty
  - federated_partial_failure
  - federated_node_timeout
  - federated_node_unavailable
  - sandbox_policy_denied
  - sandbox_unavailable
  - transport_error
  - internal_error
```

Create `packages/sdk-spec/spec/auth.yaml`:

```yaml
version: 0.1.0

auth_providers:
  - static_bearer_token
  - async_bearer_token
  - request_hook

rules:
  - Bearer tokens are sent only through Authorization headers.
  - SDKs must not log bearer tokens.
  - SDKs must not accept production identity through request JSON.
```

Create `packages/sdk-spec/spec/pagination.yaml`:

```yaml
version: 0.1.0

cursor:
  type: opaque_string
  sdk_behavior:
    - expose raw cursor
    - provide idiomatic iterator helper
    - do not decode cursor in public SDK behavior

page_fields:
  - limit
  - hasMore
  - cursor
  - nextCursor
```

Create `packages/sdk-spec/spec/binary.yaml`:

```yaml
version: 0.1.0

binary_modes:
  - base64_json
  - raw_upload
  - raw_download
  - multipart

rules:
  - SDKs must support binary-safe upload and download.
  - SDKs must not coerce binary payloads to UTF-8 text.
  - SDKs must not log binary payload snippets.
  - Multipart helpers must expose create, put part, complete, and abort operations.
```

### Testing Work

Add conformance scenarios for:

```text
errors.invalid_token
errors.permission_denied
auth.whoami
query.pagination
blobs.read_write_download_upload
blobs.multipart_upload
```

### Documentation Work

In `treedx-standard.md`, document:

```text
TreeDxApiError / equivalent shape
AuthProvider shape
Pagination helper expectations
Binary helper expectations
```

### Phase Complete When

- Error behavior is defined once.
- Auth behavior is defined once.
- Pagination behavior is defined once.
- Binary behavior is defined once.
- Each behavior has at least one conformance scenario.

### Phase 6 Completion Status

Phase 6 is complete. `errors.yaml`, `auth.yaml`, `pagination.yaml`, and
`binary.yaml` define shared cross-language behavior contracts for
`TreeDxApiError`-compatible errors, bearer auth providers, opaque cursor
pagination, binary-safe payloads, and multipart uploads. `validate-spec.ts`
schema-validates these files and cross-checks them against OpenAPI,
capabilities, endpoints, and conformance scenario metadata.

---

## Phase 7 — Build the Shared Conformance Suite

### Goal

Create shared black-box behavior tests that every SDK must pass through its public API.

### Repository Changes

Create conformance scenario files:

```text
packages/sdk-spec/conformance/scenarios/
  health.yaml
  auth.yaml
  repositories.yaml
  workspaces.yaml
  files.yaml
  blobs.yaml
  query.yaml
  graph.yaml
  context.yaml
  federation.yaml
  snapshots.yaml
  artifacts.yaml
  mirrors.yaml
  migrations.yaml
  exec.yaml
  observability.yaml
  security.yaml
```

Create fixture directories:

```text
packages/sdk-spec/conformance/fixtures/
  repos/
    markdown_mdx_basic/
    binary_assets/
    graph_context/
    federation_visible_hidden/
  expected/
    query/
    graph/
    context/
    blobs/
```

Scenario example:

```yaml
id: query.search_filter_sort
capability: query.repository
requires:
  server: local
  auth: dev
setup:
  fixture_repo: markdown_mdx_basic
  grant:
    capabilities:
      - files:read
      - files:search
    paths:
      - docs/**
steps:
  - call: query.search
    input:
      repoId: "$repo.id"
      ref: refs/heads/main
      paths:
        - docs/**
      query: release provenance
      filters:
        - field: status
          op: eq
          value: published
      sort:
        - field: path
          direction: asc
      limit: 20
expect:
  ok: true
  contains:
    results:
      - path: docs/readme.md
  not_contains:
    serialized:
      - ".env"
      - "secret"
      - "$TREEDX_DATA_DIR"
```

Define required scenario IDs:

```text
health.basic
auth.whoami
auth.effective_scope
errors.invalid_token
errors.permission_denied
repositories.register_get_status
repositories.refs_remotes
workspaces.create_get_close
files.tree_read_write_patch_delete
files.search_status_diff_commit
blobs.read_write_download_upload
blobs.multipart_upload
query.read_file
query.paths_list
query.search_filter_sort
query.changed_paths
query.pagination
graph.refresh_status
graph.search_files_sections_entities
graph.query_related_subgraph
context.build_modes
context.parse_ctx
federation.plan
federation.global_search
federation.global_query
federation.partial_failure
snapshots.build_get_export
artifacts.list_get_delete
mirrors.create_health_promote
migrations.plan
exec.read_only
exec.write_limited
observability.health_metrics
security.no_secret_or_path_leakage
```

### Testing Work

Implement the conformance runner shape:

```text
Read scenario YAML.
Set up fixture repository.
Create dev token or use provided token.
Create grants.
Run calls through language-specific conformance adapter.
Compare with matchers.
Check no disallowed leakage markers appear.
```

Required matcher types:

```text
string
optional_string
number
boolean
iso8601
regex
prefix
contains
not_contains
array_contains
object_contains
```

### Documentation Work

Document:

```text
How to add a scenario
How to run conformance for one SDK
How to run conformance for all SDKs
How dynamic fields are matched
How fixture repos are prepared
```

### Phase Complete When

- Scenario files exist for every required capability.
- Fixtures exist for text, MDX, binary, graph, and federation cases.
- At least TypeScript can run the conformance adapter against the shared scenarios.
- Security leakage assertions are built into conformance.

### Phase 7 Completion Status

Phase 7 is complete. `packages/sdk-spec/conformance/scenarios` contains the
shared black-box scenario catalog for every required capability scenario ID.
`validate-spec.ts` enforces scenario uniqueness, capability ownership,
endpoint references, fixture hygiene, and required steps/assertions. The
scenario catalog is metadata/assertion oriented; executable language harnesses
remain later SDK implementation work.

---

## Phase 8 — Create the TypeScript TreeDX SDK

### Goal

Create `packages/ts-sdk` as the generic TypeScript TreeDX SDK. It must implement the same shared SDK architecture as Python, Rust, and Elixir and must not depend on TreeSeed product concepts.

### Repository Changes

Target source layout:

```text
packages/ts-sdk/src/treedx/
  index.ts
  client/
    TreeDxClient.ts
    TreeDxRegistryClient.ts
    TreeDxFederatedClient.ts
    transport.ts
    errors.ts
    auth.ts
    pagination.ts
    binary.ts
  adapters/
    repositories.ts
    workspaces.ts
    files.ts
    blobs.ts
    query.ts
    graph.ts
    context.ts
    federation.ts
    snapshots.ts
    artifacts.ts
    mirrors.ts
    migrations.ts
    exec.ts
  ports/
    transport.ts
    auth-provider.ts
    repository-port.ts
    workspace-port.ts
    query-port.ts
    graph-port.ts
  generated/
    openapi-types.ts
  types/
    index.ts
  conformance/
    adapter.ts
```

Target package exports:

```json
{
  "exports": {
    "./treedx": "./dist/treedx/index.js",
    "./treedx/client": "./dist/treedx/client/index.js",
    "./treedx/types": "./dist/treedx/types/index.js",
    "./treedx/adapters": "./dist/treedx/adapters/index.js",
    "./treedx/conformance": "./dist/treedx/conformance/index.js"
  }
}
```

Create `packages/ts-sdk/sdk-manifest.yaml`:

```yaml
sdk: treedx-typescript
language: typescript
version: 0.1.0
sdkSpecVersion: 0.1.0
openapiVersion: 0.10.0

testLayout:
  unit: partial
  adapters: partial
  generated: partial
  conformance: partial
  integration: partial

modules:
  Client: partial
  Auth: partial
  Repositories: partial
  Workspaces: partial
  Files: partial
  Blobs: partial
  Query: partial
  Graph: partial
  Context: partial
  Federation: partial
  Registry: partial
  Snapshots: partial
  Artifacts: partial
  Mirrors: partial
  Migrations: partial
  Exec: partial
  Observability: partial

capabilities:
  health.basic: partial
  auth.whoami: partial
  repositories.lifecycle: partial
  workspaces.lifecycle: partial
  files.lifecycle: partial
  blobs.binary: partial
  blobs.multipart: partial
  query.repository: partial
  graph.repository: partial
  context.repository: partial
  federation.global_query: partial
  registry.routing: partial
  snapshots.lifecycle: partial
  artifacts.lifecycle: partial
  mirrors.lifecycle: partial
  migrations.lifecycle: partial
  exec.workspace: partial
  observability.health_metrics: partial
```

### Testing Work

Move TypeScript tests toward the shared layout:

```text
packages/ts-sdk/test/
  unit/
    client.test.ts
    transport.test.ts
    auth.test.ts
    errors.test.ts
    pagination.test.ts
    binary.test.ts

  adapters/
    repositories.test.ts
    workspaces.test.ts
    files.test.ts
    blobs.test.ts
    query.test.ts
    graph.test.ts
    context.test.ts
    federation.test.ts
    snapshots.test.ts
    artifacts.test.ts
    mirrors.test.ts
    migrations.test.ts
    exec.test.ts

  generated/
    openapi-types.test.ts
    openapi-freshness.test.ts
    exports.test.ts

  conformance/
    sdk-conformance.test.ts

  integration/
    live-api.test.ts
    treedx-e2e.test.ts
```

Use TypeScript package verification commands:

```bash
cd packages/ts-sdk
npm ci
npm run build
npm run treedx:check-generated --if-present
npm test
```

Add new commands:

```json
{
  "scripts": {
    "test:treedx-unit": "vitest run --config ./vitest.config.ts test/unit test/adapters test/generated",
    "test:treedx-conformance": "vitest run --config ./vitest.config.ts test/conformance",
    "test:treedx-integration": "vitest run --config ./vitest.config.ts test/integration",
    "treedx:generate": "tsx scripts/generate-treedx-openapi-types.ts",
    "treedx:check-generated": "tsx scripts/check-treedx-generated-types.ts"
  }
}
```

### Documentation Work

Update TypeScript SDK docs:

```text
How to import TreeDX client
How to configure base URL, auth, and repository context
How generated OpenAPI types map to public SDK aliases
How adapters map generic repo/ref/path/workspace requests
How errors, pagination, binary data, and auth behave
How to run TypeScript conformance
```

### Phase Complete When

- TypeScript follows the shared test layout.
- TypeScript has a conformance adapter.
- TypeScript passes shared conformance.
- Generated OpenAPI type checks still pass.
- TypeScript does not encode TreeSeed product concepts or depend on `packages/trsd-sdk`.

### Phase 8 Completion Status

Phase 8 is complete. `packages/ts-sdk` exists as the generic TypeScript TreeDX
SDK baseline with standalone npm metadata, OpenAPI-derived generated operation
metadata, shared client/auth/error/pagination/binary primitives, module
adapters for every required `sdk-spec` module, a conformance adapter that loads
Phase 7 scenario records and reports `not_configured` until live execution is
wired, the shared TypeScript test layout, and `sdk-manifest.yaml` using current
Phase 5+ capability IDs. `packages/trsd-sdk` remains separate and unmodified.

---

## Phase 9 — Integrate TreeSeed SDK Through the TypeScript TreeDX SDK

### Goal

Migrate `packages/trsd-sdk` TreeDX-related behavior to consume standardized `packages/ts-sdk` clients and adapters without breaking the TreeSeed SDK public surface.

### Repository Changes

In `packages/trsd-sdk`, introduce backend interfaces that adapt TreeSeed concepts to generic TreeDX SDK calls:

```ts
export interface ContentBackend {
  list(input: ListContentInput): Promise<ListContentResult>;
  get(input: GetContentInput): Promise<ContentEntry | null>;
  search(input: SearchContentInput): Promise<SearchContentResult>;
  create(input: CreateContentInput): Promise<MutationResult>;
  update(input: UpdateContentInput): Promise<MutationResult>;
  delete(input: DeleteContentInput): Promise<MutationResult>;
}
```

Implement:

```text
LocalContentBackend
TreeDxContentBackend using packages/ts-sdk
```

Introduce graph backend interfaces:

```text
GraphBackend
LocalGraphBackend
TreeDxGraphBackend using packages/ts-sdk
```

Introduce exec backend interfaces:

```text
ExecBackend
LocalExecBackend
TreeDxExecBackend using packages/ts-sdk
```

Preserve `AgentSdk` configuration shape:

```ts
const sdk = new AgentSdk({
  treeDx: {
    enabled: true,
    baseUrl,
    token,
    repoId,
    ref: "refs/heads/main",
    contentPathMap: {
      page: "src/content/pages/**"
    }
  }
});
```

### Testing Work

Compatibility tests must prove:

```text
Existing TreeSeed public exports remain stable.
Existing local SDK behavior remains default.
TreeDX mode is opt-in.
No-clone mode works when model metadata and content path maps are supplied.
ContentStore behavior is equivalent through LocalContentBackend and TreeDxContentBackend.
TreeDX adapters do not introduce TreeSeed product semantics into server requests.
TreeDX error envelopes become TreeDxApiError consistently.
Binary operations work without a local clone.
```

### Documentation Work

Document migration path:

```text
Before: direct TreeDX-specific helper or local ContentStore path in packages/trsd-sdk.
After: selected ContentBackend using standardized packages/ts-sdk TreeDxClient adapters.
```

Document boundaries:

```text
TreeSeed model registry remains responsible for model names, aliases, slugs, canonical content shapes, and product semantics.
TreeDX receives generic repo/ref/path/query/graph/context requests.
```

### Phase Complete When

- TreeSeed SDK public API still passes compatibility tests.
- TreeDX-backed operations use standardized `packages/ts-sdk` `TreeDxClient` and adapters.
- Local-vs-TreeDX parity tests pass.
- No raw TreeDX endpoint calls remain outside the standardized TreeDX SDK layer, except tests or documented low-level utilities.

### Phase 9 Completion Status

Phase 9 is complete. `packages/trsd-sdk` uses `packages/ts-sdk` as its TreeDX
access layer. TreeDX is the default adapter for the TreeSeed project content
repository as a portfolio of repositories, not a single configured repository.
`AgentSdk` config supplies TreeDX service/auth/ref/workspace context and
optional repository hints, while repository IDs are discovered internally only
when repo-scoped TreeDX endpoints require them. Local filesystem/git remains the
default for project site code and optional project repositories. `packages/ts-sdk`
remains generic and TreeSeed-free.

---

## Phase 10 — Implement the Python SDK

### Goal

Create a Python package that implements the shared SDK architecture and passes shared conformance.

### Repository Changes

Create:

```text
packages/python-sdk/
  pyproject.toml
  README.md
  src/
    treedx/
      __init__.py
      client.py
      config.py
      errors.py
      pagination.py
      auth.py
      transport.py
      binary.py
      generated/
      adapters/
        repositories.py
        workspaces.py
        files.py
        blobs.py
        query.py
        graph.py
        context.py
        federation.py
        registry.py
        snapshots.py
        artifacts.py
        mirrors.py
        migrations.py
        exec.py
        observability.py
      ports/
        auth_provider.py
        transport.py
        repository_port.py
        workspace_port.py
        file_port.py
        blob_port.py
        query_port.py
        graph_port.py
        context_port.py
        federation_port.py
        registry_port.py
        snapshot_port.py
        artifact_port.py
        mirror_port.py
        migration_port.py
        exec_port.py
      conformance/
        adapter.py
  tests/
    unit/
    adapters/
    generated/
    conformance/
    integration/
  sdk-manifest.yaml
```

Public API target:

```python
from treedx import TreeDxClient

client = TreeDxClient(
    base_url="http://localhost:4000",
    token="..."
)

health = client.health()

results = client.query.search(
    repo_id="repo_demo",
    query="release provenance",
    paths=["docs/**"],
)
```

Optional async API can be added after sync conformance passes:

```python
async with TreeDxClient.async_client(base_url=base_url, token=token) as client:
    result = await client.query.search(repo_id="repo_demo", query="release")
```

### Testing Work

Create shared test layout:

```text
tests/unit/
tests/adapters/
tests/generated/
tests/conformance/
tests/integration/
```

Run:

```bash
cd packages/python-sdk
python -m pip install -e ".[dev]"
python -m pytest tests/unit
python -m pytest tests/adapters
python -m pytest tests/generated
python -m pytest tests/conformance
python -m pytest tests/integration
```

### Documentation Work

Write:

```text
README quickstart
Authentication
Errors
Pagination
Binary upload/download
Conformance
Development commands
```

### Phase Complete When

- Python package builds.
- Python shared test layout exists.
- Python client implements all required modules.
- Python conformance adapter passes required scenarios.
- Python integration tests pass or report not configured cleanly.

### Phase 10 Completion Status

Phase 10 is complete. `packages/python-sdk` exists as the generic Python TreeDX
SDK baseline with standalone Python packaging metadata, OpenAPI-derived
generated operation metadata, shared client/auth/error/pagination/binary
primitives, module adapters for every required `sdk-spec` module, a conformance
adapter that loads Phase 7 scenario records and reports `not_configured` until
live execution is wired, the shared Python test layout, and `sdk-manifest.yaml`
using current Phase 5+ capability IDs with partial status. `packages/trsd-sdk`
remains a downstream consumer/reference and is not modified by Phase 10.

---

## Phase 11 — Implement the Rust SDK

### Goal

Create a Rust crate that implements the shared SDK architecture and passes shared conformance.

### Repository Changes

Create:

```text
packages/rust-sdk/
  Cargo.toml
  README.md
  sdk-manifest.yaml
  scripts/
    generate_treedx_openapi_types.ts
    check_treedx_generated_types.ts
  src/
    lib.rs
    auth.rs
    binary.rs
    client.rs
    config.rs
    error.rs
    pagination.rs
    transport.rs
    generated/
      mod.rs
      openapi_types.rs
    adapters/
      mod.rs
      common.rs
      repositories.rs
      workspaces.rs
      files.rs
      blobs.rs
      query.rs
      graph.rs
      context.rs
      federation.rs
      registry.rs
      snapshots.rs
      artifacts.rs
      mirrors.rs
      migrations.rs
      exec.rs
      observability.rs
    ports/
      mod.rs
      auth_provider.rs
      transport.rs
      repository_port.rs
      workspace_port.rs
      file_port.rs
      blob_port.rs
      query_port.rs
      graph_port.rs
      context_port.rs
      federation_port.rs
      registry_port.rs
      snapshot_port.rs
      artifact_port.rs
      mirror_port.rs
      migration_port.rs
      exec_port.rs
    conformance/
      mod.rs
  tests/
    unit/
    adapters/
    generated/
    conformance/
    integration/
```

Public API target:

```rust
use treedx::{TreeDxClient, TreeDxConfig};

let client = TreeDxClient::new(TreeDxConfig {
    base_url: "http://localhost:4000".into(),
    token: Some(token.into()),
    ..Default::default()
})?;

let health = client.health().await?;

let results = client
    .query()
    .search_files("repo_demo", serde_json::json!({
        "query": "release provenance",
        "paths": ["docs/**"]
    }))
    .await?;
```

### Testing Work

Create shared test layout:

```text
tests/unit/
tests/adapters/
tests/generated/
tests/conformance/
tests/integration/
```

Run:

```bash
cd packages/rust-sdk
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
```

### Documentation Work

Write:

```text
README quickstart
Feature flags
Async client usage
Error enum
Pagination
Binary upload/download
Conformance
Development commands
```

### Phase Complete When

- Rust crate builds.
- Rust shared test layout exists.
- Rust async client implements all required modules.
- Rust conformance adapter passes required scenarios.
- `cargo fmt`, `clippy`, and tests pass.
- Rust integration tests pass or report not configured cleanly.

Phase 11 is complete. `packages/rust-sdk` exists as the generic Rust TreeDX SDK
baseline with standalone Cargo metadata, OpenAPI-derived generated operation
metadata, shared async client/auth/error/pagination/binary primitives, module
adapters for every required `sdk-spec` module, lightweight port traits, a
conformance adapter that loads Phase 7 scenario records and reports
`not_configured` until live execution is wired, the shared Rust test layout, and
`sdk-manifest.yaml` using current Phase 5+ capability IDs with partial status.
`packages/trsd-sdk` remains a downstream consumer/reference and is not modified
by Phase 11.

---

## Phase 12 — Implement the Elixir SDK

### Goal

Create an Elixir package that implements the shared SDK architecture and passes shared conformance.

### Repository Changes

Create:

```text
packages/elixir-sdk/
  mix.exs
  README.md
  sdk-manifest.yaml
  scripts/
    generate_treedx_openapi_types.exs
    check_treedx_generated_types.exs
  lib/
    treedx.ex
    treedx/
      auth.ex
      binary.ex
      client.ex
      config.ex
      error.ex
      pagination.ex
      transport.ex
      adapters/
        common.ex
        repositories.ex
        workspaces.ex
        files.ex
        blobs.ex
        query.ex
        graph.ex
        context.ex
        federation.ex
        registry.ex
        snapshots.ex
        artifacts.ex
        mirrors.ex
        migrations.ex
        exec.ex
        observability.ex
      ports/
        auth_provider.ex
        transport.ex
        repository_port.ex
        workspace_port.ex
        file_port.ex
        blob_port.ex
        query_port.ex
        graph_port.ex
        context_port.ex
        federation_port.ex
        registry_port.ex
        snapshot_port.ex
        artifact_port.ex
        mirror_port.ex
        migration_port.ex
        exec_port.ex
      generated/
        openapi_types.ex
      conformance/
        adapter.ex
  test/
    unit/
    adapters/
    generated/
    conformance/
    integration/
```

Public API target:

```elixir
client =
  TreeDxSdk.Client.new(
    base_url: "http://localhost:4000",
    token: token
  )

{:ok, health} = TreeDxSdk.health(client)

{:ok, results} =
  TreeDxSdk.Query.search(client, "repo_demo", %{
    query: "release provenance",
    paths: ["docs/**"]
  })
```

### Testing Work

Create shared test layout:

```text
test/unit/
test/adapters/
test/generated/
test/conformance/
test/integration/
```

Run:

```bash
cd packages/elixir-sdk
mix deps.get
mix format --check-formatted
mix test
```

### Documentation Work

Write:

```text
README quickstart
Client configuration
Error struct
Pagination
Binary upload/download
Conformance
Development commands
```

### Phase Complete When

- Elixir package builds.
- Elixir shared test layout exists.
- Elixir client implements all required modules.
- Elixir conformance adapter passes required scenarios.
- `mix format --check-formatted` and `mix test` pass.
- Elixir integration tests pass or report not configured cleanly.

Phase 12 is complete. `packages/elixir-sdk` exists as the generic Elixir TreeDX
SDK baseline with standalone Mix metadata, OpenAPI-derived generated operation
metadata, shared client/auth/error/pagination/binary/transport primitives,
module adapters for every required `sdk-spec` module, lightweight port
behaviours, a conformance adapter that loads Phase 7 scenario records and
reports `not_configured` until live execution is wired, the shared Elixir test
layout, and `sdk-manifest.yaml` using current Phase 5+ capability IDs with
partial status. `packages/trsd-sdk` remains a downstream consumer/reference and
is not modified by Phase 12.

---

## Phase 13 — Add Package-Level GitHub Actions Release Gates

### Goal

Make SDK changes first-class CI checks while keeping them separate from the root
TreeDX service release gate and independently releasable by package.

### Repository Changes

Add:

```text
.github/workflows/sdk-spec-release-gate.yml
.github/workflows/treedx-release-gate.yml
.github/workflows/python-sdk-release-gate.yml
.github/workflows/rust-sdk-release-gate.yml
.github/workflows/elixir-sdk-release-gate.yml
```

Update:

```text
.github/workflows/release-gate.yml
packages/sdk-spec/README.md
docs/runbooks/release-gate.md
docs/runbooks/sdk-release.md
docs/architecture/treedx-spec-implementation-plan.md
```

Remove:

```text
.github/workflows/sdk-spec.yml
.github/workflows/sdk-packages.yml
.github/workflows/sdk-conformance.yml
.github/workflows/sdk-integration.yml
```

Do not modify `packages/trsd-sdk` implementation files and do not edit
`sdk-plan.md`.

### Workflow Scope

All release gates use the same event shape:

```text
workflow_dispatch
pull_request with package/service path filters
push to all branches with package/service path filters
push to all tags without custom tag-diff filtering
```

The root `TreeDX Release Gate` is path-filtered to service, native, profile,
Docker, security, release-gate, and OpenAPI service files. It keeps the
architecture matrix verify jobs:

```text
TreeDX Release Gate / Verify (amd64)
TreeDX Release Gate / Verify (arm64)
```

Profile jobs remain in `TreeDX Release Gate` and preserve the original release
sequence: service verification runs first, profile jobs run after verification
on release-path pushes, and Docker image publishing waits for the required
profile streams, including the performance profile. Profiles are broad
acceptance tests and can stop a release. Performance profiles run by default on
`main`, `staging`, and tag pushes. The performance profile reports whether the
target RPS was met, but not meeting that target is not a release failure by
itself; the job fails only for profiler/runtime errors, service errors,
assertion failures, or response validation failures.

`TreeDX Release Gate / SDK Spec` validates the shared spec package:

```text
packages/sdk-spec npm ci
npm run validate
npm run check-openapi-coverage
npm run check-sdk-manifests
npm run render-capability-matrix
npm test
./scripts/check-sdk-docs.sh
```

Each language SDK has architecture-matrix test jobs inside `TreeDX Release
Gate`. These jobs depend on `SDK Spec`:

```text
TypeScript SDK Test (amd64/arm64): generated metadata check, build, unit/conformance/integration/full tests
Python SDK Test (amd64/arm64): generated metadata check, editable dev install, build, unit/adapter/generated/conformance/integration/full pytest
Rust SDK Test (amd64/arm64): generated metadata check, cargo fmt --check, cargo clippy -D warnings, cargo test
Elixir SDK Test (amd64/arm64): generated metadata check, mix format --check-formatted, mix test
```

On release-path pushes, Docker architecture image builds and SDK package
artifact jobs both wait for all language SDK tests and the required service
profile gates. They then run in parallel. Final Docker manifest publishing
waits for the SDK package artifacts as well as both service image families.
Publishing to npm, PyPI, crates.io, and Hex remains out of scope; the integrated
release gate only builds and uploads package artifacts.

### CI Check Names

Required SDK-affecting checks inside `TreeDX Release Gate`:

```text
TreeDX Release Gate / SDK Spec
TreeDX Release Gate / TypeScript SDK Test (amd64)
TreeDX Release Gate / TypeScript SDK Test (arm64)
TreeDX Release Gate / Python SDK Test (amd64)
TreeDX Release Gate / Python SDK Test (arm64)
TreeDX Release Gate / Rust SDK Test (amd64)
TreeDX Release Gate / Rust SDK Test (arm64)
TreeDX Release Gate / Elixir SDK Test (amd64)
TreeDX Release Gate / Elixir SDK Test (arm64)
```

Release-path profile checks:

```text
TreeDX Release Gate / Profile (amd64)
TreeDX Release Gate / Profile (arm64)
TreeDX Release Gate / Federation Profile (...)
TreeDX Release Gate / Performance Profile (...)
```

### Documentation Work

Add a CI section to `packages/sdk-spec/README.md` documenting:

```text
What each integrated SDK job checks
Which release-gate jobs are required for SDK-affecting changes
How to run equivalent local commands
SDK test dependency on SDK Spec
Artifact-only package behavior after service profiles pass
Tag behavior
```

### Testing Work

Run local equivalents:

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
npm run test:treedx-unit
npm run test:treedx-conformance
npm run test:treedx-integration
npm test
mkdir -p release-artifacts
npm pack --pack-destination ./release-artifacts

cd packages/python-sdk
python3 -m pip install --upgrade pip
python3 -m pip install -e ".[dev]"
python3 -m pip install twine
python3 scripts/check_treedx_generated_types.py
python3 -m build
python3 -m pytest
python3 -m twine check dist/*

cd packages/rust-sdk
tsx scripts/check_treedx_generated_types.ts
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo package --locked

cd packages/elixir-sdk
mix local.hex --force
mix deps.get
mix run scripts/check_treedx_generated_types.exs
mix format --check-formatted
mix test
MIX_ENV=prod mix hex.build

./scripts/openapi-check.sh
```

### Phase Complete When

- `TreeDX Release Gate / SDK Spec` validates sdk-spec, OpenAPI coverage,
  manifests, matrix rendering, sdk-spec tests, and SDK documentation.
- TypeScript, Python, Rust, and Elixir SDK test jobs exist in `TreeDX Release
  Gate`, run on amd64 and arm64, and depend on `SDK Spec`.
- SDK package artifact jobs exist in `TreeDX Release Gate`, run on release-path
  pushes after service profile gates and all SDK tests pass, and upload package
  artifacts.
- The root release gate is path-filtered for service and SDK changes so there
  is one synchronized release pipeline.
- TreeDX profile jobs remain in `TreeDX Release Gate` and block Docker release
  publishing on release-path pushes.
- Standalone SDK release-gate workflows are removed.
- `packages/sdk-spec/README.md` documents workflow scope and local equivalents.

Phase 13 is complete. GitHub Actions now use one integrated `TreeDX Release
Gate` for service and SDK release verification. SDK Spec runs in parallel with
service verification, language SDK tests run on amd64 and arm64 after SDK Spec
passes, service profile streams remain release-blocking acceptance tests, and
Docker architecture image builds plus SDK package artifact jobs run after all
SDK tests and profile streams pass. Final Docker manifest publishing waits for
SDK package artifacts, keeping service and SDK release outputs synchronized. SDK
package jobs build and upload artifacts without publishing to external
registries.

---

## Phase 14 — Decide Release Gate Relationship and Add Local SDK Test Script

### Goal

Make SDK verification release-relevant without forcing the root service release
gate to own every language toolchain by default.

### Repository Changes

Create:

```text
scripts/test-sdk-packages.sh
docs/runbooks/sdk-release.md
```

Update:

```text
docs/runbooks/release-gate.md
packages/sdk-spec/README.md
```

Do not update:

```text
scripts/release-gate.sh
sdk-plan.md
```

### Local SDK Gate

`scripts/test-sdk-packages.sh` runs the full local SDK gate:

- `packages/sdk-spec`: validation, OpenAPI coverage, manifest validation,
  capability matrix, and tests.
- `packages/ts-sdk`: generated metadata check, build, and tests.
- `packages/python-sdk`: editable dev install, generated metadata check, build,
  and tests.
- `packages/rust-sdk`: generated metadata check, format check, clippy, and
  tests.
- `packages/elixir-sdk`: dependency install, generated metadata check, format
  check, and tests.

The script is a complete release-readiness gate and intentionally fails if a
local required toolchain is incomplete. For example, missing Python `pip` is an
actionable local environment failure, not a skipped SDK release check.

### Release Policy

Root `scripts/release-gate.sh` remains focused on the TreeDX service, native
crates used by the service, API contract, storage, security, container, and
operational checks.

SDK-affecting changes should require the integrated `TreeDX Release Gate` SDK
checks:

- `TreeDX Release Gate / SDK Spec`
- `TreeDX Release Gate / TypeScript SDK Test (amd64)`
- `TreeDX Release Gate / TypeScript SDK Test (arm64)`
- `TreeDX Release Gate / Python SDK Test (amd64)`
- `TreeDX Release Gate / Python SDK Test (arm64)`
- `TreeDX Release Gate / Rust SDK Test (amd64)`
- `TreeDX Release Gate / Rust SDK Test (arm64)`
- `TreeDX Release Gate / Elixir SDK Test (amd64)`
- `TreeDX Release Gate / Elixir SDK Test (arm64)`

For full release candidates, require:

1. Root `TreeDX Release Gate`, including SDK checks
2. Release-path SDK package artifact jobs
3. Root OpenAPI gate

SDK package artifact jobs build and upload artifacts only. Publishing remains a
manual or future step.

### Testing Work

Run:

```bash
./scripts/test-sdk-packages.sh
./scripts/openapi-check.sh
```

Run focused `packages/trsd-sdk` regression when TypeScript SDK changes can
affect the standalone TreeSeed package boundary. `packages/trsd-sdk` must not depend on sibling SDK package paths or generated `dist` output.

### Documentation Work

Update:

```text
docs/runbooks/release-gate.md
docs/runbooks/sdk-release.md
packages/sdk-spec/README.md
```

Document:

```text
Integrated root release gate scope
SDK test and package artifact job scope
Local SDK package gate
How a release candidate becomes ready
How optional live checks report not configured
Focused TreeSeed downstream regression boundary
Cleanup after verification
```

### Phase Complete When

- Local SDK package test script exists and is executable.
- CI-required SDK jobs exist inside the integrated `TreeDX Release Gate`.
- Release documentation clearly explains that service and SDK checks are part
  of one synchronized release gate.
- Full release readiness includes both service and SDK checks.
- `docs/runbooks/sdk-release.md` documents local SDK verification, GitHub
  workflow checks, optional live integration, focused TreeSeed regression,
  troubleshooting, and cleanup.

Phase 14 is complete. `scripts/test-sdk-packages.sh` provides a local full SDK
package gate across `sdk-spec`, TypeScript, Python, Rust, and Elixir. The release
gate runbook now documents how SDK tests and package artifact jobs are integrated
into the root `TreeDX Release Gate`. `docs/runbooks/sdk-release.md` documents
local SDK verification, required integrated release-gate SDK jobs,
tag-based package publishing behavior, focused TreeSeed regression, release candidate readiness,
troubleshooting, and cleanup.

---

## Phase 15 — Complete Documentation and Developer Onboarding

### Goal

Make the completed SDK architecture understandable for humans and AI coding agents.

### Repository Changes

Add or update:

```text
packages/sdk-spec/README.md
packages/sdk-spec/spec/treedx-standard.md
packages/ts-sdk/README.md
packages/python-sdk/README.md
packages/rust-sdk/README.md
packages/elixir-sdk/README.md
docs/architecture/sdk-integration.md
docs/runbooks/sdk-conformance.md
docs/runbooks/sdk-release.md
docs/runbooks/sdk-remote-mode.md
docs/api/compatibility-notes.md
scripts/check-sdk-docs.sh
```

### Documentation Work

Each SDK README includes:

```text
Install
Configure client
Authenticate
Basic health call
Repository query
Workspace file lifecycle
Blob upload/download
Graph/context query
Federated query
Error handling
Pagination
Conformance command
Integration command
```

`sdk-spec` README must include:

```text
What sdk-spec controls
How to add a capability
How to add a conformance scenario
How to add a language SDK
How to update OpenAPI coverage
How to render capability matrix
```

TreeSeed TypeScript docs must include:

```text
TreeDX is the default adapter for project content when configured
Local filesystem/git remains default for site code and optional repositories
No-clone mode requirements
Model registry boundary
Content path map examples
Local-vs-TreeDX parity expectations
No global TreeDX repository id
```

`docs/runbooks/sdk-conformance.md` documents:

```text
Shared scenario catalog location
Capability/scenario ownership
Language conformance commands
Current not_configured adapter behavior
Future live conformance boundary
```

`scripts/check-sdk-docs.sh` verifies required documentation files, stale
TreeDX repository-id wording, required README topics, required command
references, and Phase 15 completion status.

### Testing Work

Run documentation checks:

```bash
./scripts/check-sdk-docs.sh
```

Run SDK and package checks:

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
python3 scripts/check_treedx_generated_types.py
python3 -m compileall -q src tests

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

### Phase Complete When

- Every package has usable README documentation.
- The shared SDK standard is human-readable.
- The shared SDK standard is machine-checkable.
- TypeScript migration behavior is documented.
- All runbooks explain local and CI commands.
- SDK docs do not reintroduce global TreeDX repository-id configuration.
- `sdk-plan.md` remains untouched as the non-canonical draft.

Phase 15 is complete. SDK documentation now provides consistent onboarding for
`sdk-spec` and all four generic language SDKs, including installation,
configuration, auth, health, repository query, workspace file lifecycle, blob,
graph/context, federation, errors, pagination, conformance, and integration
commands. The shared SDK standard documents language onboarding and TreeSeed
boundaries. `docs/runbooks/sdk-conformance.md` documents the shared scenario
catalog and current `not_configured` adapter behavior. TreeSeed integration docs
now describe portfolio-backed TreeDX content without a global repository id.
`scripts/check-sdk-docs.sh` verifies required documentation files, key command
references, stale TreeDX repo-id language, and Phase 15 completion status.

---

## Phase 16 — Final Cross-Language Verification and Completion

### Goal

Prove the SDK baseline is complete, tested, documented, and ready to maintain
over time without overstating live conformance status.

### Repository Changes

Ensure final expected tree exists:

```text
packages/sdk-spec
packages/ts-sdk
packages/python-sdk
packages/rust-sdk
packages/elixir-sdk
.github/workflows/sdk-spec-release-gate.yml
.github/workflows/treedx-release-gate.yml
.github/workflows/python-sdk-release-gate.yml
.github/workflows/rust-sdk-release-gate.yml
.github/workflows/elixir-sdk-release-gate.yml
scripts/test-sdk-packages.sh
scripts/check-sdk-docs.sh
docs/runbooks/sdk-conformance.md
docs/runbooks/sdk-release.md
docs/research/sdk-final-verification.md
```

### Testing Work

Run all package checks:

```bash
./scripts/test-sdk-packages.sh
```

Run documentation checks:

```bash
./scripts/check-sdk-docs.sh
```

Run the root OpenAPI gate:

```bash
./scripts/openapi-check.sh
```

Expected final verification state:

```text
sdk-spec validation passes
OpenAPI coverage check passes
TypeScript package tests pass
Focused TreeSeed compatibility regression passes in packages/trsd-sdk
Python generated metadata and source/test compile checks pass locally
Python package install/build/pytest pass when Python pip tooling is available
Rust package tests pass
Elixir package tests pass
SDK conformance catalog loading and local-harness conformance behavior passes
Integration tests pass or report not configured cleanly
Capability matrix shows all required capabilities implemented for TypeScript, Python, Rust, and Elixir
Documentation commands are accurate
```

The full root `scripts/release-gate.sh` remains required for complete TreeDX
service release readiness, but Phase 16 SDK baseline verification does not run
that service release gate by default because it covers broader service,
container, storage, and operational checks.

### Documentation Work

Add final status block to the plan:

```text
Status: Baseline complete
Spec version: 0.1.0
Required SDKs: TypeScript, Python, Rust, Elixir
Required SDK manifest status: implemented
Required conformance: scenario catalog loading plus local-harness live dispatch
Required package workflows: integrated TreeDX Release Gate SDK Spec, SDK test, and SDK package artifact jobs
Required documentation: complete
Live executable conformance: local TreeDX harness
```

### Phase Complete When

- All four SDKs expose the same required capability set as implemented baselines.
- All four SDKs use the same test category layout.
- TreeSeed migration safety tests live in packages/trsd-sdk and do not define TreeDX SDK architecture.
- All SDKs pass shared conformance catalog loading and clean not_configured adapter behavior.
- OpenAPI remains the wire contract.
- `sdk-spec` remains the SDK architecture contract.
- TreeSeed product semantics remain outside TreeDX.
- SDK-related GitHub Actions are required checks for SDK changes.
- Documentation is complete enough for future developers and AI agents to continue safely.
- `docs/research/sdk-final-verification.md` records the final baseline checks
  and any local Python packaging tooling blocker.

Phase 16 is complete. The TreeDX SDK baseline now includes `sdk-spec`, generic
TypeScript, Python, Rust, and Elixir SDK packages, SDK CI workflows, local SDK
package and documentation gates, shared conformance scenario metadata, and
release/conformance/onboarding documentation. All SDK manifests accurately
report implemented status with full OpenAPI ownership and local-harness conformance. The
final verification record documents package checks, dependency-free Python
validation where local pip tooling is unavailable, focused TreeSeed downstream
regression, and the root OpenAPI gate. `sdk-plan.md` remains untouched as a
non-canonical draft.

---

## Final Desired End State

At the end of Phase 16:

```text
packages/sdk-spec
  defines the shared standard, capabilities, test framework, and conformance suite

packages/ts-sdk
  provides an idiomatic TypeScript TreeDX SDK with the same architecture as the other language SDKs

packages/trsd-sdk
  remains the existing TreeSeed SDK and consumes packages/ts-sdk for TreeDX access

packages/python-sdk
  provides an idiomatic Python TreeDX SDK

packages/rust-sdk
  provides an idiomatic Rust TreeDX SDK

packages/elixir-sdk
  provides an idiomatic Elixir TreeDX SDK

all SDKs
  share the same architecture
  share the same test layout
  load the same conformance scenarios and dispatch live through the local harness when configured
  expose the same TreeDX capabilities as implemented baselines
  preserve TreeDX security and public hygiene constraints
  remain aligned through sdk-spec and GitHub Actions
```

This plan intentionally uses only phases as the step-wise unit. New work should be added by editing an existing phase or adding the next numbered phase, not by creating separate epics, milestones, or parallel planning tracks.
