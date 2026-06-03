# TreeDB API Contract Versioning

TreeDB public compatibility is defined by `docs/api/openapi.yaml`, generated
SDK types, and contract tests. The API prefix is `/api/v1`.

## Contract Source

- OpenAPI is the source for TreeDB HTTP request, response, error, and resource
  payload shapes.
- The TypeScript SDK generates TreeDB API payload types from OpenAPI.
- SDK-only adapter and local-mode helper types remain SDK-owned.

## Compatibility Rules

Additive changes are compatible when:

- new response fields are optional or documented as open-map metadata;
- new request fields are optional;
- generated SDK types are regenerated;
- server and SDK contract tests pass.

Breaking changes require:

- a compatibility note in `docs/api/compatibility-notes.md`;
- a documented migration path or compatibility shim;
- SDK semver treatment appropriate for public type changes;
- a deprecation window when a field or error code is being replaced.

## Stable Error Contract

Public error envelopes always use:

```json
{
  "ok": false,
  "error": {
    "code": "permission_denied",
    "message": "Permission denied.",
    "details": {}
  }
}
```

Error codes are part of the compatibility contract.

## Non-Contractual Data

Public responses must not expose raw filesystem paths, credentials, hidden refs,
hidden paths, hidden snippets, raw stdout/stderr, or binary payload snippets.
Storage format migrations are governed separately from API versioning.

Operational endpoints are contract surfaces too. Health, readiness, metrics,
and protected diagnostics must update OpenAPI and generated SDK types in the
same change as server behavior.
