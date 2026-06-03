# SDK Integration Architecture

TreeDB remote mode stabilizes TreeDB as a remote transport for the TypeScript SDK. The SDK keeps local filesystem/Git behavior by default and activates TreeDB only when `treeDb.enabled` is true.

## Runtime Shape

`AgentSdk` normalizes TreeDB options into:

- `TreeDbClient`
- optional `TreeDbRegistryClient`
- optional `TreeDbFederatedClient`
- repository, query, graph, and workspace adapters

No-clone mode avoids constructing local content and graph runtimes. It requires explicit model metadata and content path mappings when local path derivation is not possible.

## Transport Ports

The SDK exposes port interfaces for auth, repository, repository query, graph, registry, exec, artifacts, and federation. TreeDB-backed port classes are thin wrappers around the existing TreeDB client and adapter methods.

## Contract Strategy

TreeDB HTTP payload types are generated from `docs/api/openapi.yaml` into
`packages/ts-sdk/src/treedb/generated/openapi-types.ts`. Public SDK type names
remain stable through aliases in `packages/ts-sdk/src/treedb/types.ts`.

Drift tests verify route inventory, OpenAPI schema coverage, generated type
freshness, SDK request construction, and package subpath exports.

## Boundaries

TreeDB APIs stay generic: repo, ref, path, graph, search, context, capability. Product model names remain SDK-side mapping metadata and are not serialized as TreeDB server concepts.
