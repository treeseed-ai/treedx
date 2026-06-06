# TypeScript TreeDB SDK

`@treedb/ts-sdk` is the generic TypeScript SDK for TreeDB. It implements the
shared `packages/sdk-spec` architecture, follows `docs/api/openapi.yaml`, and
does not encode TreeSeed product semantics. `packages/trsd-sdk` is a downstream
TreeSeed consumer/reference only.

The current `sdk-manifest.yaml` reports modules, capabilities, and test roots as
`implemented`. The SDK exposes all 113 `/api/v1` OpenAPI operations through
first-class module methods and a validated raw operation fallback.

## Install

This package is private in the current repo baseline:

```bash
cd packages/ts-sdk
npm ci
```

Consumers will import the package as:

```ts
import { TreeDbClient, TreeDbApiError } from '@treedb/ts-sdk';
```

## Configure Client

```ts
import { TreeDbClient } from '@treedb/ts-sdk';

const client = new TreeDbClient({
  baseUrl: 'http://localhost:4000',
  token: process.env.TREEDB_TOKEN
});
```

The client also accepts a custom auth provider, custom transport, and default
headers for tests or embedding.

## Authenticate

Bearer authentication uses the `Authorization: Bearer <token>` header. Tokens
may come from `token` or an auth provider. The SDK must not place production
identity in request JSON and must not log bearer tokens.

## Basic Health Call

```ts
const health = await client.health();
const version = await client.version();
```

## Repository Query

Repository-scoped query helpers live under `client.query`:

```ts
const result = await client.query.searchFiles('repo_demo', {
  query: 'release provenance',
  paths: ['docs/**']
});

const file = await client.query.readFile('repo_demo', {
  ref: 'refs/heads/main',
  path: 'docs/index.md'
});
```

## Workspace File Lifecycle

Workspace-scoped file helpers live under `client.workspaces` and
`client.files`:

```ts
const workspace = await client.workspaces.create('repo_demo', {
  ref: 'refs/heads/main'
});

await client.files.write('workspace_123', {
  path: 'docs/new.md',
  content: '# New'
});

await client.files.patch('workspace_123', {
  path: 'docs/new.md',
  patch: '...'
});

await client.files.commit('workspace_123', {
  message: 'Update docs'
});

await client.workspaces.close('workspace_123');
```

## Blob Upload And Download

Binary helpers preserve byte payloads and do not coerce arbitrary text strings
into binary upload bodies.

```ts
await client.blobs.upload('workspace_123', new Uint8Array([1, 2, 3]));
const blob = await client.blobs.download('workspace_123', { path: 'asset.bin' });
```

Multipart helpers expose create, part upload, complete, and abort:

```ts
const upload = await client.blobs.createMultipartUpload('workspace_123', {
  path: 'large.bin'
});

await client.blobs.uploadPart('workspace_123', upload.uploadId, 1, new Uint8Array([1]));
await client.blobs.completeMultipartUpload('workspace_123', upload.uploadId, {
  parts: [{ partNumber: 1 }]
});
```

## Graph And Context Query

```ts
await client.graph.refresh('repo_demo');
const graph = await client.graph.query('repo_demo', { query: 'MATCH ...' });
const context = await client.context.build('repo_demo', { query: 'ctx docs' });
const parsed = await client.context.parse('repo_demo', { source: 'ctx docs' });
```

## Federated Query

Federation helpers use portfolio/global TreeDB routes rather than a single
configured repository:

```ts
const plan = await client.federation.plan({ query: 'release provenance' });
const results = await client.federation.search({ query: 'release provenance' });
```

## Scoped Admin And Internal Modules

Full OpenAPI coverage includes sensitive scoped modules: Admin, Audit, Policy,
SearchIndex, and FederationInternal. These APIs require appropriate TreeDB
credentials and should be used carefully against production systems. They remain
generic TreeDB APIs and do not encode TreeSeed product semantics.

The raw operation fallback validates method/path pairs against generated OpenAPI
metadata before dispatch.

## Error Handling

Non-2xx responses and network failures surface as `TreeDbApiError` with
`status`, `code`, `message`, `details`, and `payload`. Network failures use
`status = 0` and `code = "network_error"`.

```ts
try {
  await client.whoami();
} catch (error) {
  if (error instanceof TreeDbApiError) {
    console.error(error.status, error.code, error.message);
  }
}
```

## Pagination

Pagination helpers preserve opaque cursor values and page metadata. SDK code
must not decode TreeDB cursor internals.

```ts
import { getNextCursor } from '@treedb/ts-sdk/treedb/client';
```

## Binary And Multipart

Binary bodies may be `Uint8Array`, `ArrayBuffer`, `Buffer`, or
`ReadableStream<Uint8Array>`. Multipart part numbers are passed through to
TreeDB without SDK renumbering.

## Conformance

The shared scenario catalog loads through `TreeDbConformanceAdapter`. Live
conformance runs against the local TreeDB harness for implemented SDK
verification. Optional integration checks may still report a clean
not-configured path when no server is configured.

```bash
npm run test:treedb-conformance
```

## Integration

Integration tests call a live TreeDB server only when `TREEDB_BASE_URL` is set.
Without that environment variable, they pass cleanly by reporting
not-configured behavior.

```bash
npm run test:treedb-integration
```

## Development Commands

```bash
npm ci
npm run treedb:check-generated
npm run build
npm run test:treedb-unit
npm run test:treedb-conformance
npm run test:treedb-integration
npm test
```
