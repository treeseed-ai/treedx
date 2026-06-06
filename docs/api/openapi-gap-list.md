# TreeDX OpenAPI Gap List

Status: Typed contract coverage inventory

`docs/api/openapi.yaml` is the public TreeDX HTTP contract. SDK API payload
types are generated from that file into
`packages/ts-sdk/src/treedx/generated/openapi-types.ts`.

## Typed Contract Coverage

Every public route in `apps/api/lib/treedx_web/router.ex` must appear in
OpenAPI with:

- `operationId`
- `summary`
- `x-treedx-required-capabilities`
- route-specific success response schema
- typed error envelope
- request schemas where the route accepts JSON
- binary response metadata for raw byte routes
- operational health, readiness, and metrics response schemas

Route and schema drift is checked by:

- `apps/api/test/treedx_web/route_openapi_inventory_test.exs`
- `apps/api/test/treedx_web/openapi_contract_test.exs`
- `packages/ts-sdk/test/utils/treedx-openapi-contract.test.ts`
- `packages/ts-sdk/test/utils/treedx-generated-types.test.ts`
- `packages/ts-sdk/test/utils/treedx-sdk-request-contract.test.ts`

## Missing Error Examples

Add examples for:

- `authentication_required`
- `invalid_token`
- `permission_denied`
- `workspace_revoked`
- `not_found`
- `conflict`
- `validation_error`
- `unsupported_media_type`
- `payload_too_large`
- `graph_not_ready`
- `unsupported_transport`
- `sandbox_unavailable`
- `sandbox_policy_denied`
- `backup_failed`
- `storage_compaction_failed`

## Known Intentional Open Maps

Some response fragments intentionally remain open maps because they contain
opaque diagnostics, extension options, audit event data, or remote metadata.
These use `additionalProperties: true` and must still pass public hygiene
tests.

Intentional open-map areas:

- audit event `data`
- federation filters and diagnostics
- graph and context options
- storage diagnostics
- error `details`

## Generated SDK Type Coverage

Generated type freshness is checked with:

```bash
cd packages/ts-sdk
npm run treedx:check-types
```

Public SDK type names remain stable through aliases in
`packages/ts-sdk/src/treedx/types.ts`.

## Remaining Contract Work

Remaining work is limited to quality improvements rather than broad schema gaps:

- add richer examples for rare operational errors;
- expand live infrastructure conformance tests;
- tighten intentionally open diagnostic maps as server payloads become stable;
- consider generated Phoenix validators if runtime schema validation becomes
  useful.
