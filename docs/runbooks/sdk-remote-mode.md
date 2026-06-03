# SDK Remote Mode Runbook

## Required Inputs

- TreeDB base URL
- Bearer token
- Repository ID
- SDK model registry or model definitions
- Content path map for no-clone content models

## Smoke Check

```bash
TREEDB_LIVE_URL=http://localhost:4000 \
TREEDB_LIVE_TOKEN=... \
TREEDB_LIVE_REPO_ID=repo_demo \
./scripts/sdk-live-contract.sh
```

Without those environment variables, the script reports `not configured` and
exits successfully. This is an operational check result, not a skipped test.

## Mutating Check

```bash
TREEDB_LIVE_MUTATING=true \
TREEDB_LIVE_WRITE_PATH=tmp/sdk-live.md \
./scripts/sdk-live-contract.sh
```

Use a test repository or an isolated branch policy for mutating checks.

## Troubleshooting

- `missing_repo_id`: set `repoId` on `treeDb` or `TreeDbClientOptions`.
- `missing_content_path_mapping`: add `contentPathMap` for absolute model paths in no-clone mode.
- `permission_denied`: verify TreeDB token capabilities and path/ref scopes.
- `timeout`: increase `timeoutMs` or inspect TreeDB/server network health.
- `network_error`: verify base URL and connectivity.
