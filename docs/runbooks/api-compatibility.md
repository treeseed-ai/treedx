# TreeDB API Compatibility Runbook

Use this runbook when changing TreeDB public routes or payload types.

## Required Steps

1. Update `docs/api/openapi.yaml`.
2. Add or update server contract tests.
3. Coordinate SDK type generation and SDK client changes in the independent SDK
   repository when public payloads change.
4. Record breaking or compatibility-sensitive changes in
   `docs/api/compatibility-notes.md`.
5. Run `./scripts/test-treedb-fast.sh`.

## Additive Changes

Optional request fields and optional response fields are usually compatible.
Document the field and verify contract tests. Coordinate SDK updates separately
when the field is part of SDK-facing behavior.

## Breaking Changes

Changing required fields, removing fields, renaming routes, changing error
codes, or changing response envelope keys requires a compatibility note and a
coordinated SDK compatibility decision.

## Safety Checks

Before handoff, search for implementation-history labels and remove them from
TreeDB implementation artifacts. Planning archives may retain historical
wording, but public docs, tests, code, scripts, OpenAPI metadata, and generated
types should use unified contract language.
