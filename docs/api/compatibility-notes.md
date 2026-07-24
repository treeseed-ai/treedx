# TreeDX API Compatibility Notes

## Current Contract

- TreeDX API path prefix: `/api/v1`
- OpenAPI source of truth: `docs/api/openapi.yaml`
- SDK architecture source of truth: `packages/sdk-spec`
- Declared SDK endpoint format: `METHOD /api/v1/path`
- Error envelopes and stable OpenAPI error codes are public compatibility
  surfaces.
- Generated-like OpenAPI operation metadata is maintained in every generic
  language SDK.

## Generic SDK Packages

Generic TreeDX SDK packages are:

- TypeScript: `@treedx/treedx`
- Python: `treedx` with import package `treedx`
- Rust: crate `treedx` with library `treedx`
- Elixir: app `:treedx` with namespace `TreeDxSdk`

These packages expose generic TreeDX concepts only: repositories, refs, paths,
workspaces, blobs, query, graph, context, federation, registry, snapshots,
artifacts, mirrors, migrations, exec, and observability.

## Downstream TreeSeed Package

`@treeseed/sdk` in `packages/trsd-sdk` is downstream. It may consume
`@treedx/treedx` and may keep TreeSeed compatibility tests, but it does not
define generic TreeDX SDK architecture.

TreeSeed portfolio-backed content is downstream compatibility behavior. TreeDX
is treated as a portfolio of repositories; TreeSeed service configuration does
not require a single global repository id.

## Compatibility Expectations

- Additive OpenAPI response fields are compatible when documented and optional.
- SDK generated metadata must be refreshed when `/api/v1` operations change.
- SDK capability endpoint ownership must stay aligned with
  `packages/sdk-spec/spec/capabilities.yaml`.
- Public error `status`, `code`, `message`, `details`, and `payload` fields must
  remain available across SDKs.
- Federation catalogs and route responses expose logical node, repository,
  route, capacity, and mirror metadata only.
- SDKs and TreeDX responses must not expose storage paths, credentials, user
  tokens, node tokens, delegated tokens, hidden paths, snippets, stdout/stderr,
  request bodies, or binary payload snippets.

## Compatibility Gates

Run generic SDK gates:

```bash
./scripts/verification/test-sdk-packages.sh
./scripts/verification/check-sdk-docs.sh
```

Run the root OpenAPI gate:

```bash
./scripts/verification/openapi-check.sh
```
