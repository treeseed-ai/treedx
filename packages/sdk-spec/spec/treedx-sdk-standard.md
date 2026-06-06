# TreeDX SDK Standard

## Purpose

Define the shared architecture, endpoint ownership, test layout, and conformance
scaffolding for TreeDX SDKs across TypeScript, Python, Rust, and Elixir.

## Non-Goals

This standard does not generate SDK code, define TreeSeed product semantics, or
replace `docs/api/openapi.yaml`. OpenAPI remains the wire contract.

## Package Roles

`packages/sdk-spec` owns the shared standard. Language SDK packages implement the
standard. `packages/trsd-sdk` is a downstream TreeSeed integration reference and
future consumer, not an architecture owner.

## TreeSeed Boundary

TreeSeed integration lives in `packages/trsd-sdk`. That package may consume a
generic TreeDX SDK and may keep downstream compatibility tests, but TreeSeed
model names, content registry semantics, UI/site workflow behavior, and product
compatibility expectations must not define the generic TreeDX SDK architecture.

The generic SDKs stay TreeDX-only: repositories, refs, paths, workspaces, graph,
context, federation, blobs, snapshots, artifacts, mirrors, migrations, exec, and
observability.

## Common SDK Architecture

Every language SDK uses generated, core, facade, and conformance layers. The
generated layer validates or derives low-level operation shapes from OpenAPI.
The core layer owns shared TreeDX behavior. The facade layer exposes idiomatic
language APIs. The conformance layer adapts shared scenarios to each SDK.

Canonical layer directories:

```text
generated/
core/
facade/
conformance/
```

Module ownership is defined in `architecture.yaml` and summarized here:

| Module | Primary Capability | Owned Port |
| --- | --- | --- |
| Client | health.basic | transport |
| Auth | auth.whoami | auth_provider |
| Repositories | repositories.lifecycle | repository_adapter |
| Workspaces | workspaces.lifecycle | workspace_adapter |
| Files | files.lifecycle | file_adapter |
| Blobs | blobs.binary | blob_adapter |
| Query | query.repository | query_adapter |
| Graph | graph.repository | graph_adapter |
| Context | context.repository | context_adapter |
| Federation | federation.global_query | federation_adapter |
| Registry | registry.routing | registry_adapter |
| Snapshots | snapshots.lifecycle | snapshot_adapter |
| Artifacts | artifacts.lifecycle | artifact_adapter |
| Mirrors | mirrors.lifecycle | mirror_adapter |
| Migrations | migrations.lifecycle | migration_adapter |
| Exec | exec.workspace | exec_adapter |
| Observability | observability.health_metrics | transport |

## Capability Coverage

Capability IDs are lowercase dotted identifiers such as
`repositories.lifecycle` and `blobs.multipart`. A required capability is the
unit of SDK completeness across TypeScript, Python, Rust, and Elixir.

Every required SDK capability must define:

- one owning module from `architecture.yaml`;
- `type: sdk`;
- `required: true`;
- one or more endpoint strings in `METHOD /api/v1/path` format;
- one or more conformance scenario IDs.

Endpoint strings must exactly match `docs/api/openapi.yaml`. Declared endpoints
are strict; OpenAPI routes that are not yet represented by SDK capabilities are
advisory uncovered routes until later endpoint coverage phases.

The capability matrix renders one status column per language SDK. Missing
language SDK manifests render as `not_configured`. Existing manifests that omit
a required capability render that capability as `missing`.

| Matrix Status | Meaning |
| --- | --- |
| implemented | The language SDK reports the capability implemented |
| partial | The language SDK reports partial capability support |
| planned | The language SDK reports future capability support |
| not_applicable | The language SDK reports the capability as intentionally not applicable |
| missing | A manifest exists but omits the capability |
| not_configured | No manifest exists for the language SDK |

## Generated Layer

Generated OpenAPI clients are not the entire public SDK. SDKs may generate types
or low-level request shapes, but public APIs must preserve the shared concepts in
this standard. They are a generated or generated-like layer under the shared
architecture. Public SDKs must still provide consistent auth, errors,
pagination, binary, adapter, and conformance behavior.

## Core Layer

The core layer owns transport, auth, error handling, pagination, binary data,
and adapters for TreeDX modules. Core module ownership is machine-readable in
`architecture.yaml`; every required module has a direct capability entry and at
least one owned port.

## Public Facade Layer

The public facade should feel idiomatic in each language while preserving the
same endpoint coverage, error behavior, and conformance semantics.

## Language SDK Onboarding

Each language SDK must provide:

- standalone package metadata for its ecosystem;
- `sdk-manifest.yaml` with every required module, capability, and test root;
- generated-like OpenAPI operation metadata derived from
  `docs/api/openapi.yaml`;
- client, auth, error, pagination, binary, transport, adapter, port, generated,
  conformance, and integration surfaces matching this standard;
- a conformance adapter that loads shared scenario records through the public SDK
  facade and reports clean `not_configured` behavior until live dispatch exists;
- test roots from `testing.yaml`.

Required language package roots:

| Language | Package | Public Package Name |
| --- | --- | --- |
| TypeScript | `packages/ts-sdk` | `@treedx/ts-sdk` |
| Python | `packages/python-sdk` | `treedx-sdk` / `treedx_sdk` |
| Rust | `packages/rust-sdk` | `treedx-sdk` / `treedx_sdk` |
| Elixir | `packages/elixir-sdk` | `:treedx_sdk` / `TreeDxSdk` |

Manifest status values are `implemented`, `partial`, `planned`, and
`not_applicable`. Baseline SDK packages may use `partial` while live conformance
dispatch remains deferred.

## Auth Contract

SDKs support bearer tokens and may expose auth provider abstractions. Production
identity must not be supplied through request JSON.

| Behavior | Requirement |
| --- | --- |
| Bearer token header | Authorization |
| Bearer token scheme | Bearer |
| Production identity in JSON | Forbidden |
| Token logging | Forbidden |
| Connected auth | Generic auth provider behavior only |

## Transport Contract

Transport implementations send OpenAPI-aligned HTTP requests and preserve
TreeDX response envelopes, binary bodies, and error metadata.

## Error Contract

SDKs expose `TreeDxApiError`-compatible failures with status, code, message,
details, and payload.

| Field | Meaning |
| --- | --- |
| status | HTTP status code, or 0 for network failures |
| code | Stable TreeDX error code from OpenAPI |
| message | Human-readable diagnostic |
| details | Structured diagnostics when available |
| payload | Original error payload when available and safe |

## Pagination Contract

Cursors are opaque. SDKs may expose language-idiomatic pagination helpers but
must preserve server-owned cursor values.

| Concept | Requirement |
| --- | --- |
| TreeDxCursor | Opaque server-owned string |
| TreeDxPage.items | Preserved result items |
| TreeDxPage.nextCursor | Exposed without decoding |
| TreeDxPage.hasMore | Preserved when returned |
| Iterators | Stop cleanly when no next cursor is available |

## Binary and Multipart Contract

SDKs must move blob bytes without text coercion and expose multipart create,
part upload, complete, and abort operations.

| Behavior | Requirement |
| --- | --- |
| Binary body | Byte-safe language-native value |
| Upload/download | No UTF-8 coercion |
| Logging | No binary payload snippets |
| Multipart | Create, put part, complete, abort |
| Part numbers | Passed through without SDK renumbering |

## Repository Contract

Repository APIs cover registration, creation, listing, inspection, status, refs,
and remotes.

## Workspace Contract

Workspace APIs cover create, inspect, and close lifecycle behavior.

## File Contract

File APIs cover tree listing, read, write, patch, delete, search, status, diff,
and commit behavior.

## Blob Contract

Blob APIs cover repository blob reads, workspace blob writes/deletes,
downloads/uploads, and multipart upload sessions.

## Query Contract

Query APIs cover repository file reads, path listing, file search, and generic
repository query execution.

## Graph Contract

Graph APIs cover refresh and repository graph query behavior.

## Context Contract

Context APIs cover context build and context query parsing behavior.

## Federation Contract

Federation APIs cover global search, query, graph, context, and query planning.

## Snapshot Contract

Snapshot APIs cover building and retrieving repository snapshots.

## Artifact Contract

Artifact APIs cover export, list, get, and delete behavior.

## Mirror Contract

Mirror APIs cover list, create/update, sync, health, and promote behavior.

## Migration Contract

Migration APIs cover repository placement migration creation and retrieval.

## Exec Contract

Exec APIs cover workspace-scoped command execution under TreeDX policy
boundaries.

## Observability Contract

Observability APIs cover health, readiness, deep health, and metrics.

## Shared Test Framework

Language SDKs share unit, adapters, generated, conformance, and integration test
roots. Downstream consumers may add compatibility tests.

| Category | Required | Server | Purpose |
| --- | --- | --- | --- |
| unit | yes | no | Pure SDK behavior |
| adapters | yes | no | Mocked transport request/response behavior |
| generated | yes | no | OpenAPI type freshness and exports |
| conformance | yes | conditional | Shared scenarios through public SDK API |
| integration | yes | yes | Real TreeDX server tests |
| compatibility | no | conditional | Downstream product SDK migration safety |

| Language | Root | Required Layout |
| --- | --- | --- |
| TypeScript | test | test/unit, test/adapters, test/generated, test/conformance, test/integration |
| Python | tests | tests/unit, tests/adapters, tests/generated, tests/conformance, tests/integration |
| Rust | tests | tests/unit, tests/adapters, tests/generated, tests/conformance, tests/integration |
| Elixir | test | test/unit, test/adapters, test/generated, test/conformance, test/integration |

| Status | Meaning |
| --- | --- |
| implemented | Root exists and contains tests or placeholder test marker |
| partial | Root exists but does not need full test coverage yet |
| planned | Root may be absent |
| not_applicable | Root may be absent and must be justified by manifest metadata later |

Compatibility tests are for downstream product SDK migration safety, such as
TreeSeed integration tests in `packages/trsd-sdk`. They must not define the
TreeDX language SDK architecture or replace shared conformance.

## Conformance Rules

Conformance scenarios are shared black-box behavior records. They have unique
IDs, map to capability IDs, reference only endpoints owned by those
capabilities, and define required public-facade steps and assertions.

Generated OpenAPI clients are not the direct conformance surface. Each language
SDK must expose a conformance adapter that drives scenarios through the SDK's
public facade without bypassing normal auth, transport, error, pagination, and
binary behavior.

Required scenario metadata:

| Field | Requirement |
| --- | --- |
| id | Unique lowercase dotted scenario id |
| capabilityId | Existing capability id from `capabilities.yaml` |
| kind | `black_box` |
| required | Boolean SDK requirement flag |
| serverRequired | `true`, `false`, or `conditional` |
| endpointRefs | Endpoint strings owned by the capability |
| fixtures | `repos`, `requests`, and `expected` arrays |
| steps | Non-empty public SDK facade actions |
| assertions | Non-empty behavioral assertions |

Fixtures must stay generic and avoid credentials, absolute paths, parent
directory traversal, local machine paths, and TreeSeed product semantics. Phase
7 defines scenario metadata and behavioral assertions; executable language
harnesses and populated fixture payloads arrive in later SDK implementation
work.

## Documentation Requirements

Every language SDK README must include:

- install and development setup;
- client configuration;
- auth behavior;
- a basic health call;
- repository query examples;
- workspace file lifecycle examples;
- blob upload/download and multipart behavior;
- graph/context query examples;
- federated query examples;
- error handling;
- pagination;
- conformance command;
- integration command and not-configured behavior.

`packages/sdk-spec/README.md` must document how to add capabilities,
conformance scenarios, language SDKs, OpenAPI coverage, and matrix rendering.
SDK release and conformance runbooks must document local and CI commands.

## Versioning Policy

The spec version is additive during the draft phase. Breaking changes require a
version bump and corresponding language SDK manifest updates.
