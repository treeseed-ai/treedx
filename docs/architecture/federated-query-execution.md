# Federated Query Execution

Stage 4 moves federation from planning-only to authorized execution for global
search, query, context, and graph routes.

Execution always starts with scope reduction. TreeDB resolves the caller's
effective policy for each requested repository, ref, path, and capability before
any repository content is read. Unauthorized repositories and paths are rejected
before query, ranking, graph expansion, context packing, diagnostics, and
serialization.

## Routing

Repositories placed on the local node execute in-process through the existing
single-repository modules. Repositories placed on another node execute over HTTP
using the node `baseUrl` in the registry.

Remote requests receive only the reduced repo/ref/path scope. The original
requested paths are never forwarded when they are outside the effective scope.
Bearer forwarding is enabled by default through
`TREEDB_FEDERATION_FORWARD_AUTH=true`.

## Partial Failures

When `includeErrors=true`, remote failures are returned as sanitized per-repo
partial errors. When `includeErrors=false`, any remote failure fails the whole
request with `federated_partial_failure`.

Public responses and audit payloads must not include remote URLs, credentials,
local paths, hidden path names, hidden snippets, hidden graph IDs, or raw remote
response bodies.

## Graph IDs

Federated graph nodes and edges use qualified IDs:

```text
treedb://repo/<repo_id>/node/<id>
treedb://repo/<repo_id>/edge/<id>
```

Cross-repo edges are emitted only when both endpoint repositories and endpoint
nodes are present in the authorized result set.
