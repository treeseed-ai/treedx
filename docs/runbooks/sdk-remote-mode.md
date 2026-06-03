# SDK Remote Mode Runbook

## Required Inputs

- TreeDB base URL
- Bearer token
- Repository ID
- SDK model registry or model definitions
- Content path map for no-clone content models

## Smoke Check

SDK live checks are run by the independent SDK package workflow. The top-level
TreeDB release gate does not invoke SDK scripts or require an SDK checkout.

## Mutating Check

Use a test repository or an isolated branch policy for mutating checks.

## Troubleshooting

- `missing_repo_id`: set `repoId` on `treeDb` or `TreeDbClientOptions`.
- `missing_content_path_mapping`: add `contentPathMap` for absolute model paths in no-clone mode.
- `permission_denied`: verify TreeDB token capabilities and path/ref scopes.
- `timeout`: increase `timeoutMs` or inspect TreeDB/server network health.
- `network_error`: verify base URL and connectivity.
