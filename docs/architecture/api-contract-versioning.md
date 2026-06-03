# TreeDB API Contract Versioning

TreeDB public compatibility is defined by `docs/api/openapi.yaml` and contract
tests. The API prefix is `/api/v1`.

## Contract Source

- OpenAPI is the source for TreeDB HTTP request, response, error, and resource
  payload shapes.
- SDK payload types and client adapters are generated and verified in the
  independent SDK workflow.

## Compatibility Rules

Additive changes are compatible when:

- new response fields are optional or documented as open-map metadata;
- new request fields are optional;
- server contract tests pass;
- SDK compatibility work is coordinated separately when public payloads change.

Breaking changes require:

- a compatibility note in `docs/api/compatibility-notes.md`;
- a documented migration path or compatibility shim;
- coordinated SDK semver treatment when public type changes affect SDK users;
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
and protected diagnostics must update OpenAPI in the same change as server
behavior. SDK updates are handled in the independent SDK workflow when needed.
