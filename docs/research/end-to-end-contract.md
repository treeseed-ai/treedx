# End-To-End Contract

## Purpose

The end-to-end contract proves that a repository can be registered, queried,
updated, indexed, snapshotted, audited, federated, and replayed without putting
TreeSeed product semantics into TreeDX.

## Current Baseline

The baseline includes dev and connected auth, scoped capabilities, audit
listing, repository query, workspace file/blob operations, graph/context
segments, search indexes, snapshots/artifacts, mirror sync records, push/fetch,
placement migration records, storage operations, global federation execution,
and TypeScript SDK TreeDX clients.

## Verification Shape

The required fast layer is:

- `apps/api/test/treedx_web/end_to_end_mvp_test.exs`
- `packages/ts-sdk/test/utils/treedx-e2e-contract.test.ts`

The optional deployment layer is:

- `scripts/mvp-smoke.sh`
- `packages/ts-sdk/test/utils/treedx-live-contract.test.ts` when live env vars are set

## Federation Scope

Federation tests verify both planner behavior and authorized global execution.
Requested repositories, refs, paths, and capabilities are reduced to authorized
scope before search, query, context, or graph execution.

## Fixture Repository Shape

The dynamic fixture repository contains:

- Markdown and MDX files
- YAML frontmatter
- headings and Markdown links
- a generic unresolved `treedx://` reference
- `treedx provenance` as a unique searchable phrase
- files outside a restricted actor path scope

Shell Git is used only to create this test fixture repository.

## Required Sequence

The fast test covers auth, policy, node and placement lookup, workspace
creation, repository search, graph refresh, context build, federation
planning/execution, file and blob writes, exec, status/diff, commit,
committed-ref reads, graph refresh/search on the committed branch, snapshot
build, artifact export, migration dry-run, audit listing, and replay.

## Restart And Recovery

The restart check calls `TreeDx.Store.init!/1` against the same data directory and verifies repository, placement, audit events, latest graph manifest, and snapshot manifest replay.

## SDK No-Clone Contract

The SDK mocked test constructs `TreeDxClient`, `TreeDxRepositoryAdapter`, and `TreeDxGraphAdapter` without a local repository clone. Content model path routing is provided through `contentPathMap`.

## Boundary

TreeSeed product-domain semantics remain outside TreeDX. Live checks are
environment-backed and report `not configured` when credentials are absent.

## Verification Commands

```bash
CARGO_TARGET_DIR=/tmp/treedx-target cargo test --workspace
cd apps/api
CARGO_TARGET_DIR=/tmp/treedx-target RUSTLER_TARGET_DIR=/tmp/treedx-target mix test test/treedx_web/end_to_end_mvp_test.exs
cd ../..
cd packages/ts-sdk
npx vitest run --config ./vitest.config.ts test/utils/treedx-e2e-contract.test.ts test/utils/treedx-live-contract.test.ts
```
