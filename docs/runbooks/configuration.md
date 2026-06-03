# TreeDB Configuration Runbook

TreeDB configuration is environment-variable driven.

Core settings:

- `TREEDB_DATA_DIR`
- `TREEDB_AUTH_MODE`
- `TREEDB_STORAGE_MODE`
- `TREEDB_EXEC_BACKEND`
- `TREEDB_NODE_ID`
- `PHX_HOST`
- `PORT`

Operational settings:

- `TREEDB_HEALTH_CHECK_AUTH_PROVIDER=false`
- `TREEDB_HEALTH_CHECK_TIMEOUT_MS=2000`

Use `/api/v1/ready` to verify traffic readiness and
`/api/v1/admin/health/deep` with a `policy:read` token for protected
diagnostics. Public responses must show logical or redacted values only.

## CI/CD Secrets

The root TreeDB workflow uses GitHub's `production` environment only for Docker
publishing after all tests pass.

Required production environment secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

The root workflow does not require npm, Node, or the ignored TypeScript SDK
package.
