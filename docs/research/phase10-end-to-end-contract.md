# Phase 10 End-To-End Contract

## Purpose

Phase 10 turns the Phase 1-9 TreeDB surfaces into a repeatable MVP proof that a repository can be registered, queried, updated, indexed, snapshotted, audited, and replayed without putting TreeSeed product semantics into TreeDB.

## Current Phase 9 Baseline

The baseline includes dev and connected auth, scoped capabilities, audit listing, repository query, workspace file operations, graph/context segments, snapshots/artifacts, mirror sync records, placement migration records, and TypeScript SDK TreeDB clients.

## Verification Shape

The required fast layer is:

- `apps/api/test/treedb_web/end_to_end_mvp_test.exs`
- `packages/ts-sdk/test/utils/treedb-e2e-contract.test.ts`

The optional deployment layer is:

- `scripts/phase10-smoke.sh`
- `packages/ts-sdk/test/utils/treedb-live-contract.test.ts` when live env vars are set

## Federation Scope

Global federation execution remains out of scope. Phase 10 only verifies planner behavior: requested repositories, refs, paths, and capabilities are reduced to authorized scopes before any future query execution.

## Fixture Repository Shape

The dynamic fixture repository contains:

- Markdown and MDX files
- YAML frontmatter
- headings and Markdown links
- a generic unresolved `treedb://` reference
- `phase ten provenance` as a unique searchable phrase
- files outside a restricted actor path scope

Shell Git is used only to create this test fixture repository.

## Required Sequence

The fast test covers auth, policy, node and placement lookup, workspace creation, repository search, graph refresh, context build, federation planning, file write, read-only and verification exec, status/diff, commit, committed-ref reads, graph refresh/search on the committed branch, snapshot build, artifact export, migration dry-run, audit listing, and restart-style replay.

## Restart And Recovery

The restart check calls `TreeDb.Store.init!/1` against the same data directory and verifies repository, placement, audit events, latest graph manifest, and snapshot manifest replay.

## SDK No-Clone Contract

The SDK mocked test constructs `TreeDbClient`, `TreeDbRepositoryAdapter`, and `TreeDbGraphAdapter` without a local repository clone. Content model path routing is provided through `contentPathMap`.

## Non-Goals

- global `/api/v1/search`, `/api/v1/query`, or `/api/v1/context/build`
- live multi-node federation
- Git push
- production sandbox hardening
- JWKS/key rotation
- OpenAPI generation
- TreeSeed product-domain semantics inside TreeDB

## Verification Commands

```bash
CARGO_TARGET_DIR=/tmp/treedb-target cargo test --workspace
cd apps/api
CARGO_TARGET_DIR=/tmp/treedb-target RUSTLER_TARGET_DIR=/tmp/treedb-target mix test test/treedb_web/end_to_end_mvp_test.exs
cd ../..
cd packages/ts-sdk
npx vitest run --config ./vitest.config.ts test/utils/treedb-e2e-contract.test.ts test/utils/treedb-live-contract.test.ts
```
