# TreeDB API Compatibility Runbook

Use this runbook when changing TreeDB public routes, SDK methods, or payload
types.

## Required Steps

1. Update `docs/api/openapi.yaml`.
2. Run `npm run treedb:generate-types` in `packages/ts-sdk`.
3. Update SDK code only through public aliases in `packages/ts-sdk/src/treedb/types.ts`.
4. Add or update server and SDK contract tests.
5. Record breaking or compatibility-sensitive changes in
   `docs/api/compatibility-notes.md`.
6. Run `./scripts/test-treedb-fast.sh`.

## Additive Changes

Optional request fields and optional response fields are usually compatible.
Document the field, regenerate SDK types, and verify contract tests.

## Breaking Changes

Changing required fields, removing fields, renaming routes, changing error
codes, or changing response envelope keys requires a compatibility note and an
SDK semver decision.

## Safety Checks

Before handoff, search for implementation-history labels and remove them from
TreeDB implementation artifacts. Planning archives may retain historical
wording, but public docs, tests, code, scripts, OpenAPI metadata, and generated
types should use unified contract language.
