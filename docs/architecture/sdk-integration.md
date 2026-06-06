# SDK Integration Architecture

TreeDX is the default adapter for the TreeSeed project content repository. The
TreeSeed SDK configures the TreeDX service, auth, optional ref/workspace
context, content path maps, and repository-selection hints. It does not
configure one global repository id.

`packages/ts-sdk` remains the generic TypeScript TreeDX SDK. `packages/trsd-sdk`
is a downstream TreeSeed consumer that uses `@treedx/ts-sdk` for TreeDX access
and keeps TreeSeed product semantics out of the generic SDK architecture.

## Runtime Shape

`AgentSdk` normalizes TreeDX options into:

- `TreeDxClient`
- optional `TreeDxRegistryClient`
- optional `TreeDxFederatedClient`
- portfolio repository discovery through `TreeDxPortfolioResolver`
- content, graph, and exec backends that call the generic TreeDX SDK

TreeDX is a portfolio of repositories. Repository ids are discovered internally
through TreeDX APIs such as repository listing, registry placement, and
portfolio search. Repo-scoped TreeDX endpoints receive repository ids only after
that discovery step.

## Local Filesystem Boundary

Local filesystem/git remains the default for:

- project site source files;
- build, watch, and deploy code;
- optional project repositories;
- embedded repositories or submodules maintained by agents;
- GitHub automation and repository operations.

`AgentSdk.createLocal()` and `contentRepository.adapter = 'local'` force local
content behavior. Local mode remains supported for fixture sites, local-only
development, and workflows that do not configure a TreeDX service.

## TreeDX Content Configuration

TreeDX-backed content uses service-level configuration:

```ts
const sdk = new AgentSdk({
  treeDx: {
    baseUrl: 'http://localhost:4000',
    token: process.env.TREESEED_TREEDX_TOKEN,
    ref: 'refs/heads/main',
    workspaceId: process.env.TREESEED_TREEDX_WORKSPACE_ID,
    contentPathMap: {
      page: 'src/content/pages/**'
    },
    repositoryHints: [
      { purpose: 'project_content', name: 'project-content' }
    ]
  }
});
```

Supported environment variables:

```text
TREESEED_TREEDX_BASE_URL
TREESEED_TREEDX_TOKEN
TREESEED_TREEDX_REF
TREESEED_TREEDX_WORKSPACE_ID
```

There is intentionally no repository-id environment variable. Content path maps
and repository hints narrow discovery when the TreeDX portfolio contains
multiple candidates.

## No-Clone And Model Registry Boundary

No-clone content behavior requires enough local TreeSeed metadata to map model
names to content paths. TreeSeed model definitions, aliases, slugs, frontmatter
normalization, filters, and product behavior remain in `packages/trsd-sdk`.
TreeDX receives generic repository, ref, path, graph, search, context, and
workspace requests.

## Local-vs-TreeDX Parity Expectations

TreeDX content reads should preserve TreeSeed model behavior after local
frontmatter parsing and model normalization. Writes require either a workspace
or unambiguous repository discovery. If multiple repositories match a write
target, TreeSeed must fail clearly and require stronger repository hints or a
workspace.

`pick()` remains local-lease backed until TreeDX exposes a generic SDK lease
capability for TreeSeed content claims.

## Contract Strategy

TreeDX wire behavior remains defined by `docs/api/openapi.yaml`. Generic SDK
architecture remains defined by `packages/sdk-spec`. Drift checks verify route
inventory, OpenAPI schema coverage, generated-like operation metadata, request
construction, SDK manifests, and conformance scenario catalog loading.

TreeDX APIs stay generic: repo, ref, path, workspace, graph, search, context,
capability, and federation. Product model names are mapping metadata in
`packages/trsd-sdk`; they are not TreeDX server concepts.
