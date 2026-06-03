# Federation Routing Runbook

Stage 4 global federation routes:

```text
POST /api/v1/search
POST /api/v1/query
POST /api/v1/context/build
POST /api/v1/graph/query
```

## Configuration

```text
TREEDB_FEDERATION_HTTP_TIMEOUT_MS=5000
TREEDB_FEDERATION_MAX_REPOS=25
TREEDB_FEDERATION_MAX_REMOTE_REPOS=10
TREEDB_FEDERATION_FORWARD_AUTH=true
TREEDB_FEDERATION_ENABLE_REMOTE_HTTP=true
```

## Operations

1. Confirm all participating nodes are present in `/api/v1/registry/nodes`.
2. Confirm repository placements point at the intended primary node.
3. Use `/api/v1/federation/query/plan` to inspect reduced scope without
   execution.
4. Use `includeErrors=true` during diagnosis to receive sanitized partial
   failures.
5. Check audit events named `federated.*.partial` when routes fail.

## Safety Checks

Remote routes must never expose:

- bearer tokens
- remote base URLs in public errors
- local filesystem paths
- hidden path names
- hidden snippets
- hidden graph IDs
- raw remote response bodies
