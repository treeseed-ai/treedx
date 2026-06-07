# TreeDX SDK Spec and Multi-Language SDK Implementation Plan

Status: Draft v0.1  
Date: 2026-06-05  
Intended location: `docs/architecture/treedx-sdk-spec-implementation-plan.md` or Canvas  
Primary packages: `packages/sdk-spec`, `packages/ts-sdk`, `packages/python-sdk`, `packages/rust-sdk`, `packages/elixir-sdk`

## Purpose

Create one shared TreeDX SDK standard and four language-specific SDK packages that stay aligned over time:

- TypeScript
- Python
- Rust
- Elixir

This plan uses one step-wise development unit only: **phases**. Each phase includes its goal, expected repository changes, testing work, documentation work, and completion checks. There are no separate epics, milestones, or parallel planning units.

The completed implementation should provide:

- A shared `packages/sdk-spec` standard.
- A TypeScript TreeDX SDK implementation aligned with the existing TreeSeed SDK.
- New Python, Rust, and Elixir TreeDX SDK packages.
- A shared SDK test framework.
- A shared conformance suite.
- GitHub Actions workflows for package, generated-contract, conformance, integration, and documentation checks.
- Documentation that explains SDK architecture, package usage, conformance, and release responsibilities.

## Current Situation and Planning Constraints

TreeDX already has a strong API and SDK foundation:

- TreeDX public compatibility is based on `docs/api/openapi.yaml`, contract tests, stable error envelopes, and stable error codes.
- SDK payload types and client adapters are generated and verified in an independent SDK workflow.
- The current TypeScript SDK uses generated OpenAPI-backed TreeDX API types, no-clone `AgentSdk` remote mode, TreeDX-backed ports, registry routing, and global federation methods.
- TypeScript currently remains the reference SDK because it already integrates TreeDX remote mode with TreeSeed SDK behavior.
- Existing TreeSeed SDK behavior must remain stable. TreeDX should provide a repository transport/backend, not replace the developer-facing TreeSeed SDK surface with raw TreeDX endpoints.
- TreeDX APIs must stay generic: repo, ref, path, graph, search, context, and capability. TreeSeed model names, aliases, product concepts, market concepts, and workflow semantics must remain SDK-side or application-side.
- The current root release gate verifies the TreeDX service repository. The TypeScript SDK package has independent CI/CD, so SDK package workflows need to become required checks for SDK changes without making the root TreeDX release gate depend on every language toolchain by default.
- The repository docs consistently refer to `packages/ts-sdk`. If `packages/trsd-sdk` is intended as a different package name, settle that naming during Phase 1 and update this plan before implementation begins.

## Phase 1 — Establish the Baseline and Naming Decisions

### Goal

Make the current state explicit before introducing new packages, new specs, or new workflows.

### Repository Changes

Create a planning document at one of:

```text
docs/architecture/treedx-sdk-spec-implementation-plan.md
docs/research/treedx-sdk-spec-implementation-plan.md
```

Record the baseline:

```text
packages/ts-sdk
  existing npm package
  existing TreeSeed SDK public surface
  existing TreeDX remote-mode implementation
  existing generated OpenAPI type flow
  existing package graph and TreeDX contract tests

docs/api/openapi.yaml
  current TreeDX wire contract

docs/architecture/sdk-integration.md
  current TypeScript SDK TreeDX remote-mode architecture

docs/research/sdk-integration-design.md
  current AgentSdk / TreeDX mode design

docs/research/sdk-baseline-verification.md
  current TypeScript SDK verification baseline
```

Resolve package naming:

```text
Option A: keep packages/ts-sdk as the TypeScript SDK package
Option B: rename or add packages/trsd-sdk if that is the intended TreeSeed SDK package
```

Recommended decision:

```text
Keep packages/ts-sdk as the existing TypeScript implementation package.
Use packages/sdk-spec for the standard.
Add packages/python-sdk, packages/rust-sdk, and packages/elixir-sdk.
```

### Testing Work

Run and record the current TypeScript SDK baseline:

```bash
cd packages/ts-sdk
npm ci
npm run build
npm test
```

Run and record TreeDX API contract checks:

```bash
./scripts/openapi-check.sh
cd apps/api && mix test test/treedx_web/openapi_contract_test.exs
cd apps/api && mix test test/treedx_web/route_openapi_inventory_test.exs
```

### Documentation Work

Add a short “SDK naming and baseline” note to the plan:

```text
The repository currently uses packages/ts-sdk for the existing TypeScript SDK.
The new sdk-spec package will define shared SDK architecture.
The TypeScript SDK remains the reference implementation and compatibility bridge.
```

### Phase Complete When

- Package names are decided.
- Current TypeScript SDK verification status is documented.
- Current TreeDX OpenAPI contract verification status is documented.
- The plan has one canonical implementation path and no unresolved package-name ambiguity.

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
    treedx-sdk-standard.md
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
    validate-spec.mjs
    render-capability-matrix.mjs
    check-openapi-coverage.mjs
    check-sdk-manifest.mjs
```

Add `packages/sdk-spec/package.json`:

```json
{
  "name": "@treedx/sdk-spec",
  "private": true,
  "type": "module",
  "scripts": {
    "validate": "node scripts/validate-spec.mjs",
    "check-openapi-coverage": "node scripts/check-openapi-coverage.mjs",
    "check-sdk-manifests": "node scripts/check-sdk-manifest.mjs",
    "render-capability-matrix": "node scripts/render-capability-matrix.mjs",
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

Create `packages/sdk-spec/spec/treedx-sdk-standard.md` with sections:

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

---

## Phase 4 — Define the Shared Test Framework

### Goal

Use the same test architecture for all language SDKs.

The TypeScript SDK may have extra compatibility tests for TreeSeed migration safety, but its core SDK tests must follow the same structure as Python, Rust, and Elixir.

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
    description: Migration-specific tests for preserving existing public SDK behavior.

language_roots:
  typescript: test
  python: tests
  rust: tests
  elixir: test

rules:
  - All SDKs must implement unit, adapters, generated, conformance, and integration categories.
  - TypeScript may additionally implement compatibility tests for existing TreeSeed SDK behavior.
  - Compatibility tests must not define the cross-language architecture.
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
  compatibility/
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

Add `packages/sdk-spec/scripts/check-sdk-manifest.mjs` checks:

```text
Each SDK manifest declares all required test roots.
TypeScript may declare compatibility.
Python/Rust/Elixir must not require compatibility unless explicitly justified.
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
compatibility: TypeScript-only TreeSeed migration safety
```

### Phase Complete When

- The test framework is defined once in `sdk-spec`.
- All four SDKs have the same required test categories.
- TypeScript’s extra compatibility category is documented as migration-only.

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
      - migrations.dry_run

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

Implement `check-openapi-coverage.mjs`:

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

In `treedx-sdk-standard.md`, document:

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
migrations.dry_run
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

---

## Phase 8 — Align the TypeScript SDK as the Reference Implementation

### Goal

Make `packages/ts-sdk` implement the shared SDK architecture without breaking existing TreeSeed SDK users.

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
  unit: implemented
  adapters: implemented
  generated: implemented
  conformance: implemented
  integration: implemented
  compatibility: implemented

capabilities:
  health.basic: implemented
  auth.whoami: implemented
  repositories.lifecycle: implemented
  workspaces.lifecycle: implemented
  files.lifecycle: implemented
  blobs.binary: implemented
  blobs.multipart: implemented
  query.repository: implemented
  graph.context: implemented
  federation.global_query: implemented
  snapshots.artifacts: implemented
  mirrors.migrations: implemented
  exec.workspace: implemented
  observability.health_metrics: implemented
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

  compatibility/
    package-graph.test.ts
    agent-sdk-treedx-mode.test.ts
    content-store-treedx-backend.test.ts
    local-vs-treedx-parity.test.ts
    existing-treeseed-exports.test.ts
```

Preserve current verification commands:

```bash
cd packages/ts-sdk
npm run build
npx vitest run --config ./vitest.config.ts test/compatibility/package-graph.test.ts test/integration/treedx-e2e.test.ts
npm test
```

Add new commands:

```json
{
  "scripts": {
    "test:treedx-unit": "vitest run --config ./vitest.config.ts test/unit test/adapters test/generated",
    "test:treedx-conformance": "vitest run --config ./vitest.config.ts test/conformance",
    "test:treedx-integration": "vitest run --config ./vitest.config.ts test/integration",
    "treedx:generate": "node scripts/generate-treedx-openapi-types.mjs",
    "treedx:check-generated": "node scripts/check-treedx-generated-types.mjs"
  }
}
```

### Documentation Work

Update TypeScript SDK docs:

```text
How to import TreeDX client
How to use TreeDX mode
How local mode remains default
How no-clone mode works
How TreeDX adapters map model requests to repo/ref/path queries
How to run TypeScript conformance
```

### Phase Complete When

- TypeScript follows the shared test layout.
- TypeScript still passes existing TreeSeed SDK compatibility tests.
- TypeScript has a conformance adapter.
- TypeScript passes shared conformance.
- Generated OpenAPI type checks still pass.
- TreeDX mode remains opt-in and local mode remains default.

---

## Phase 9 — Replace Existing TreeDX Functionality Behind the TypeScript TreeDX SDK Layer

### Goal

Migrate existing TypeScript TreeDX-related behavior behind standardized `ts-sdk` TreeDX clients and adapters without breaking the TreeSeed SDK public surface.

### Repository Changes

Introduce backend interfaces:

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
TreeDxContentBackend
```

Introduce graph backend interfaces:

```text
GraphBackend
LocalGraphBackend
TreeDxGraphBackend
```

Introduce exec backend interfaces:

```text
ExecBackend
LocalExecBackend
TreeDxExecBackend
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
Before: direct TreeDX-specific helper or local ContentStore path.
After: selected ContentBackend using standardized TreeDxClient adapters.
```

Document boundaries:

```text
TreeSeed model registry remains responsible for model names, aliases, slugs, canonical content shapes, and product semantics.
TreeDX receives generic repo/ref/path/query/graph/context requests.
```

### Phase Complete When

- TreeSeed SDK public API still passes compatibility tests.
- TreeDX-backed operations use standardized `TreeDxClient` and adapters.
- Local-vs-TreeDX parity tests pass.
- No raw TreeDX endpoint calls remain outside the standardized TreeDX SDK layer, except tests or documented low-level utilities.

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
    treedx_sdk/
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
        snapshots.py
        artifacts.py
        mirrors.py
        migrations.py
        exec.py
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
from treedx_sdk import TreeDxClient

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
  src/
    lib.rs
    client.rs
    config.rs
    error.rs
    transport.rs
    auth.rs
    pagination.rs
    binary.rs
    generated/
    adapters/
      repositories.rs
      workspaces.rs
      files.rs
      blobs.rs
      query.rs
      graph.rs
      context.rs
      federation.rs
      snapshots.rs
      artifacts.rs
      mirrors.rs
      migrations.rs
      exec.rs
    conformance/
      mod.rs
  tests/
    unit/
    adapters/
    generated/
    conformance/
    integration/
  sdk-manifest.yaml
```

Public API target:

```rust
use treedx_sdk::{TreeDxClient, TreeDxConfig};

let client = TreeDxClient::new(TreeDxConfig {
    base_url: "http://localhost:4000".into(),
    token: Some(token.into()),
    ..Default::default()
})?;

let health = client.health().await?;

let results = client
    .query()
    .search("repo_demo")
    .query("release provenance")
    .paths(["docs/**"])
    .send()
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
  lib/
    treedx_sdk.ex
    treedx_sdk/
      client.ex
      config.ex
      error.ex
      transport.ex
      auth.ex
      pagination.ex
      binary.ex
      generated/
      repositories.ex
      workspaces.ex
      files.ex
      blobs.ex
      query.ex
      graph.ex
      context.ex
      federation.ex
      snapshots.ex
      artifacts.ex
      mirrors.ex
      migrations.ex
      exec.ex
      conformance/
        adapter.ex
  test/
    unit/
    adapters/
    generated/
    conformance/
    integration/
  sdk-manifest.yaml
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

---

## Phase 13 — Add GitHub Actions for SDK Spec, Packages, Conformance, and Integration

### Goal

Make SDK changes first-class CI checks.

### Repository Changes

Add `.github/workflows/sdk-spec.yml`:

```yaml
name: SDK Spec

on:
  pull_request:
    paths:
      - "packages/sdk-spec/**"
      - "docs/api/openapi.yaml"
      - ".github/workflows/sdk-spec.yml"
  push:
    branches: [main]
    paths:
      - "packages/sdk-spec/**"
      - "docs/api/openapi.yaml"

jobs:
  validate-sdk-spec:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "24"
          cache: npm
          cache-dependency-path: packages/sdk-spec/package-lock.json
      - run: npm ci
        working-directory: packages/sdk-spec
      - run: npm run validate
        working-directory: packages/sdk-spec
      - run: npm run check-openapi-coverage
        working-directory: packages/sdk-spec
      - run: npm run render-capability-matrix
        working-directory: packages/sdk-spec
```

Add `.github/workflows/sdk-packages.yml`:

```yaml
name: SDK Packages

on:
  pull_request:
    paths:
      - "packages/sdk-spec/**"
      - "packages/ts-sdk/**"
      - "packages/python-sdk/**"
      - "packages/rust-sdk/**"
      - "packages/elixir-sdk/**"
      - "docs/api/openapi.yaml"
      - ".github/workflows/sdk-packages.yml"
  push:
    branches: [main]

jobs:
  typescript-sdk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-node@v4
        with:
          node-version: "24"
          cache: npm
          cache-dependency-path: packages/ts-sdk/package-lock.json
      - run: npm ci
        working-directory: packages/ts-sdk
      - run: npm run build
        working-directory: packages/ts-sdk
      - run: npm run treedx:check-generated --if-present
        working-directory: packages/ts-sdk
      - run: npm test
        working-directory: packages/ts-sdk

  python-sdk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: python -m pip install -e ".[dev]"
        working-directory: packages/python-sdk
      - run: python -m pytest tests/unit tests/adapters tests/generated
        working-directory: packages/python-sdk

  rust-sdk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - run: cargo fmt --all -- --check
        working-directory: packages/rust-sdk
      - run: cargo clippy --all-targets -- -D warnings
        working-directory: packages/rust-sdk
      - run: cargo test
        working-directory: packages/rust-sdk

  elixir-sdk:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          otp-version: "27"
          elixir-version: "1.17.3"
      - run: mix deps.get
        working-directory: packages/elixir-sdk
      - run: mix format --check-formatted
        working-directory: packages/elixir-sdk
      - run: mix test
        working-directory: packages/elixir-sdk
```

Add `.github/workflows/sdk-conformance.yml`:

```yaml
name: SDK Conformance

on:
  pull_request:
    paths:
      - "packages/sdk-spec/**"
      - "packages/ts-sdk/**"
      - "packages/python-sdk/**"
      - "packages/rust-sdk/**"
      - "packages/elixir-sdk/**"
      - "apps/api/**"
      - "crates/**"
      - "docs/api/openapi.yaml"
      - ".github/workflows/sdk-conformance.yml"
  push:
    branches: [main]

jobs:
  conformance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Build TreeDX API
        run: docker compose build treedx-api

      - name: Start TreeDX API
        run: docker compose up -d treedx-api

      - name: Wait for readiness
        run: |
          for i in {1..60}; do
            curl -fsS http://localhost:4000/api/v1/ready && exit 0
            sleep 2
          done
          docker compose logs treedx-api
          exit 1

      - name: Run TypeScript conformance
        run: |
          cd packages/ts-sdk
          npm ci
          npm run test:treedx-conformance

      - name: Run Python conformance
        run: |
          cd packages/python-sdk
          python -m pip install -e ".[dev]"
          python -m pytest tests/conformance

      - name: Run Rust conformance
        run: |
          cd packages/rust-sdk
          cargo test --test conformance

      - name: Run Elixir conformance
        run: |
          cd packages/elixir-sdk
          mix deps.get
          mix test test/conformance

      - name: Stop TreeDX API
        if: always()
        run: docker compose down
```

### Testing Work

Make workflows pass in order:

```text
sdk-spec.yml
sdk-packages.yml
sdk-conformance.yml
```

### Documentation Work

Add a CI section to `packages/sdk-spec/README.md`:

```text
What each workflow checks
Which workflow is required for which change type
How to run equivalent local commands
```

### Phase Complete When

- SDK spec workflow passes.
- SDK package workflow passes.
- SDK conformance workflow passes.
- GitHub branch protection can require these checks for SDK-related changes.

---

## Phase 14 — Decide Release Gate Relationship and Add Local SDK Test Script

### Goal

Make SDK verification release-relevant without forcing the root service release gate to own every language toolchain by default.

### Repository Changes

Create:

```text
scripts/test-sdk-packages.sh
```

```bash
#!/usr/bin/env bash
set -euo pipefail

(
  cd packages/sdk-spec
  npm ci
  npm run validate
  npm run check-openapi-coverage
  npm run render-capability-matrix
)

(
  cd packages/ts-sdk
  npm ci
  npm run build
  npm run treedx:check-generated --if-present
  npm test
)

(
  cd packages/python-sdk
  python -m pip install -e ".[dev]"
  python -m pytest tests/unit tests/adapters tests/generated
)

(
  cd packages/rust-sdk
  cargo fmt --all -- --check
  cargo clippy --all-targets -- -D warnings
  cargo test
)

(
  cd packages/elixir-sdk
  mix deps.get
  mix format --check-formatted
  mix test
)
```

Recommended release policy:

```text
Root scripts/release-gate.sh remains focused on the TreeDX service, native crates, API contract, storage, security, container, and operational checks.

SDK workflows become required GitHub checks for SDK-affecting changes.

For full release candidates, require:
1. root TreeDX release gate
2. SDK spec workflow
3. SDK packages workflow
4. SDK conformance workflow
5. SDK integration workflow when configured
```

### Testing Work

Run:

```bash
./scripts/test-sdk-packages.sh
./scripts/release-gate.sh
```

### Documentation Work

Update:

```text
docs/runbooks/release-gate.md
docs/runbooks/sdk-release.md
packages/sdk-spec/README.md
```

Document:

```text
Root release gate scope
SDK package workflow scope
How a release candidate becomes ready
How optional live checks report not configured
```

### Phase Complete When

- Local SDK package test script exists.
- CI-required SDK workflows exist.
- Release documentation clearly separates TreeDX service gate from SDK package gates.
- Full release readiness includes both service and SDK checks.

---

## Phase 15 — Complete Documentation and Developer Onboarding

### Goal

Make the completed SDK architecture understandable for humans and AI coding agents.

### Repository Changes

Add or update:

```text
packages/sdk-spec/README.md
packages/sdk-spec/spec/treedx-sdk-standard.md
packages/ts-sdk/README.md
packages/python-sdk/README.md
packages/rust-sdk/README.md
packages/elixir-sdk/README.md
docs/architecture/sdk-integration.md
docs/runbooks/sdk-conformance.md
docs/runbooks/sdk-release.md
docs/api/compatibility-notes.md
```

### Documentation Work

Each SDK README must include:

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
Local mode remains default
TreeDX mode is opt-in
No-clone mode requirements
Model registry boundary
Content path map examples
Local-vs-TreeDX parity expectations
```

### Testing Work

Add documentation checks:

```text
README code snippets compile where practical.
SDK commands listed in docs match package scripts.
Capability matrix renders without stale SDK manifest data.
```

### Phase Complete When

- Every package has usable README documentation.
- The shared SDK standard is human-readable.
- The shared SDK standard is machine-checkable.
- TypeScript migration behavior is documented.
- All runbooks explain local and CI commands.

---

## Phase 16 — Final Cross-Language Verification and Completion

### Goal

Prove the implementation is complete, tested, documented, and ready to maintain over time.

### Repository Changes

Ensure final expected tree exists:

```text
packages/sdk-spec
packages/ts-sdk
packages/python-sdk
packages/rust-sdk
packages/elixir-sdk
.github/workflows/sdk-spec.yml
.github/workflows/sdk-packages.yml
.github/workflows/sdk-conformance.yml
scripts/test-sdk-packages.sh
docs/runbooks/sdk-conformance.md
docs/runbooks/sdk-release.md
```

### Testing Work

Run all package checks:

```bash
./scripts/test-sdk-packages.sh
```

Run TreeDX service gate:

```bash
./scripts/release-gate.sh
```

Run conformance:

```bash
# via GitHub Actions, or locally if the conformance runner supports it
```

Expected final verification state:

```text
sdk-spec validation passes
OpenAPI coverage check passes
TypeScript package tests pass
TypeScript compatibility tests pass
Python package tests pass
Rust package tests pass
Elixir package tests pass
All SDK conformance suites pass
Integration tests pass or report not configured cleanly
Capability matrix shows all required capabilities implemented
Documentation commands are accurate
```

### Documentation Work

Add final status block to the plan:

```text
Status: Implemented
Spec version: 0.1.0
Required SDKs: TypeScript, Python, Rust, Elixir
Required conformance: passing
Required package workflows: passing
Required documentation: complete
```

### Phase Complete When

- All four SDKs implement the same required capability set.
- All four SDKs use the same test category layout.
- TypeScript has additional compatibility tests only for TreeSeed migration safety.
- All SDKs pass shared conformance.
- OpenAPI remains the wire contract.
- `sdk-spec` remains the SDK architecture contract.
- TreeSeed product semantics remain outside TreeDX.
- SDK-related GitHub Actions are required checks for SDK changes.
- Documentation is complete enough for future developers and AI agents to continue safely.

---

## Final Desired End State

At the end of Phase 16:

```text
packages/sdk-spec
  defines the shared standard, capabilities, test framework, and conformance suite

packages/ts-sdk
  remains the TypeScript reference implementation and TreeSeed compatibility bridge

packages/python-sdk
  provides an idiomatic Python TreeDX SDK

packages/rust-sdk
  provides an idiomatic Rust TreeDX SDK

packages/elixir-sdk
  provides an idiomatic Elixir TreeDX SDK

all SDKs
  share the same architecture
  share the same test layout
  pass the same conformance scenarios
  expose the same TreeDX capabilities
  preserve TreeDX security and public hygiene constraints
  remain aligned through sdk-spec and GitHub Actions
```

This plan intentionally uses only phases as the step-wise unit. New work should be added by editing an existing phase or adding the next numbered phase, not by creating separate epics, milestones, or parallel planning tracks.
