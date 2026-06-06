# SDK Portfolio-Backed Content Runbook

TreeDX-backed TreeSeed content treats TreeDX as a portfolio of repositories.
TreeSeed configures the service, auth, optional ref/workspace context, content
path maps, and repository hints. It does not configure one global repository id.

## Required Inputs

- TreeDX base URL
- Bearer token when the TreeDX service requires auth
- Optional ref, such as `refs/heads/main`
- Optional workspace ID for write operations
- Content path map for TreeSeed content models
- Optional repository hints to narrow portfolio discovery

Supported environment variables:

```text
TREESEED_TREEDX_BASE_URL
TREESEED_TREEDX_TOKEN
TREESEED_TREEDX_REF
TREESEED_TREEDX_WORKSPACE_ID
```

There is intentionally no repository-id environment variable. Repository ids are
discovered internally by portfolio APIs only when repo-scoped TreeDX endpoints
require them.

## Configuration Example

```ts
const sdk = new AgentSdk({
  treeDx: {
    baseUrl: process.env.TREESEED_TREEDX_BASE_URL,
    token: process.env.TREESEED_TREEDX_TOKEN,
    ref: process.env.TREESEED_TREEDX_REF,
    workspaceId: process.env.TREESEED_TREEDX_WORKSPACE_ID,
    contentPathMap: {
      page: 'src/content/pages/**',
      knowledge: {
        paths: ['src/content/knowledge/**'],
        repositoryHints: [{ purpose: 'project_content' }]
      }
    },
    repositoryHints: [
      { purpose: 'project_content', name: 'project-content' }
    ]
  }
});
```

## Smoke Check

SDK live checks are run by the independent SDK package workflow. The top-level
TreeDX release gate does not invoke SDK scripts or require an SDK checkout.

For TreeSeed focused regression, keep `packages/trsd-sdk` standalone. Do not add local file links from TreeSeed SDK code to sibling SDK packages.

## Mutating Check

Use a workspace ID for content writes. Without a workspace, writes may proceed
only when repository discovery resolves exactly one candidate. If multiple
repositories match a write target, the SDK must fail clearly and require
stronger repository hints or a workspace.

Use a test repository or an isolated branch policy for mutating checks.

## Troubleshooting

- `missing_treedx_base_url`: configure `TREESEED_TREEDX_BASE_URL` or pass
  `treeDx.baseUrl`.
- `missing_content_path_mapping`: add `contentPathMap` for model paths that
  cannot be derived locally.
- `ambiguous_repository_selection`: add stronger `repositoryHints` or supply a
  `workspaceId` for writes.
- `permission_denied`: verify TreeDX token capabilities and path/ref scopes.
- `timeout`: increase timeout settings or inspect TreeDX/server network health.
- `network_error`: verify base URL and connectivity.
