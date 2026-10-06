# Federated Query Runbook

Global federation endpoints execute only after reducing requested
repo/ref/path scope to the caller's effective authorization:

- `POST /api/v1/search`
- `POST /api/v1/query`
- `POST /api/v1/context/build`
- `POST /api/v1/graph/query`

Remote HTTP routing requires node `baseUrl` configuration. Partial failures are
returned only when `includeErrors=true`; otherwise remote failures fail the
whole request.

For live multi-node validation, set:

```text
TREEDX_LIVE_NODE_A_URL
TREEDX_LIVE_NODE_A_TOKEN
TREEDX_LIVE_NODE_A_REPO_ID
TREEDX_LIVE_NODE_B_URL
TREEDX_LIVE_NODE_B_TOKEN
TREEDX_LIVE_NODE_B_REPO_ID
```

Then run:

```bash
./scripts/acceptance/federation-live-check.sh
```
