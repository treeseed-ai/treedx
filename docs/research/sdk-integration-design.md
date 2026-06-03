# SDK TreeDB Integration Design

This document records the original SDK integration design. The current SDK uses
generated OpenAPI-backed TreeDB API types, no-clone `AgentSdk` remote mode,
TreeDB-backed ports, registry routing, and global federation methods.

## Current SDK Construction

`AgentSdk` currently constructs a local `ContentStore` and `ContentGraphRuntime` in `packages/ts-sdk/src/sdk.ts`.

- `ContentStore` handles content-backed model operations through local filesystem reads/writes, Markdown/MDX walking, frontmatter parsing, local worktree paths, and `GitRuntime`.
- `ContentGraphRuntime` handles local graph snapshots under `.treeseed/state/graph`.
- Public SDK exports are declared in `packages/ts-sdk/src/index.ts` and package subpaths in `packages/ts-sdk/package.json`.
- `scripts/build-dist.ts` builds all `src/**/*.ts` into `dist`, so a new `src/treedb` namespace can be exported without extra build plumbing.

## TreeDB Integration Choice

TreeDB clients, adapters, and ports are exported. Local SDK behavior remains
unchanged by default.

TreeDB mode is opt-in through explicit client/adapters or `AgentSdk({ treeDb: { enabled: true, ... } })`. TreeDB repository transport is separate from TreeSeed market dispatch and does not overload market/project remote dispatch.

## TreeDB Endpoint Mapping

- `TreeDbClient.health` -> `GET /api/v1/health`
- `TreeDbClient.whoami` -> `GET /api/v1/auth/whoami`
- `TreeDbClient.effectiveScope` -> `GET /api/v1/policy/effective-scope`
- `TreeDbClient.getNode` -> `GET /api/v1/node`
- `TreeDbClient.getPlacement` -> `GET /api/v1/registry/repos/:repo_id/placement`
- Repository read/query methods -> `POST /api/v1/repos/:repo_id/files/read`, `/paths/list`, `/files/search`, `/query`
- Workspace methods -> `/api/v1/repos/:repo_id/workspaces` and `/api/v1/workspaces/:workspace_id/...`
- Graph/context methods -> `/api/v1/repos/:repo_id/graph/...` and `/api/v1/repos/:repo_id/context/...`

Client methods return ergonomic payloads with `ok` removed where applicable, while preserving compound response fields such as `repoId`, `results`, `nodes`, `edges`, and `page`.

## Model Registry Boundary

TreeDB is repository/ref/path/workspace scoped. It returns generic repository, file, query, graph, and context results.

The SDK model registry remains responsible for product model names, aliases, content directories, field aliases, slugs, and canonical SDK shapes. TreeDB adapters translate SDK model requests into generic TreeDB path/frontmatter/body/query requests.

## No-Clone Remote Mode

Low-level `TreeDbClient`, registry/federated clients, and adapter classes do not require a local repository clone.

`AgentSdk` TreeDB wiring still needs model definitions. Callers can provide `models` or `modelRegistry`. If an SDK model has an absolute `contentDir`, adapters derive a repository-relative path from `repoRoot` when possible; otherwise callers can provide `contentPathMap`.

## Error And Auth Behavior

TreeDB bearer tokens are passed as `authorization: Bearer <token>`.

TreeDB API error envelopes are converted to `TreeDbApiError` with status, code, message, details, and payload. Network failures are wrapped as `TreeDbApiError` with `status = 0` and `code = "network_error"` so SDK callers can handle all TreeDB client failures consistently.

Important server codes preserved by the SDK include `authentication_required`,
`invalid_token`, `permission_denied`, `workspace_revoked`, `not_found`,
`conflict`, `payload_too_large`, `unsupported_media_type`, `validation_error`,
`service_unavailable`, federation errors, sandbox errors, storage errors, and
transport errors.

## Registry Routing

`TreeDbRegistryClient` resolves repository placement through existing registry endpoints.

`TreeDbFederatedClient` uses TreeDB registry and global endpoints for federated
read/query workflows. Write federation remains scoped to the configured
repository/placement surfaces.

Global `/api/v1/search`, `/api/v1/query`, `/api/v1/context/build`, and
`/api/v1/graph/query` are implemented. Multi-repository SDK calls delegate to
TreeDB instead of client-side fan-out.

## Test Strategy

SDK tests include mocked request contract coverage, generated OpenAPI type
freshness checks, package-local verification, and optional live contract checks
that report `not configured` when credentials are absent.

Existing local SDK tests remain local. The earlier package-graph self-reference failure is documented in `docs/research/sdk-baseline-verification.md` and has been fixed; the full SDK suite now passes.
