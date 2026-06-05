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

Runtime resource and performance tuning settings:

- `TREEDB_RUNTIME_CPU_BUDGET`
- `TREEDB_RUNTIME_MEMORY_BUDGET_MB`
- `TREEDB_CACHE_MEMORY_FRACTION=0.25`
- `TREEDB_CACHE_MIN_FREE_MEMORY_MB=512`
- `TREEDB_REPO_DOC_CACHE_ENABLED=true`
- `TREEDB_REPO_DOC_CACHE_MAX_ENTRIES=256`
- `TREEDB_REPO_DOC_CACHE_MAX_BYTES`
- `TREEDB_GRAPH_INDEX_CACHE_ENABLED=true`
- `TREEDB_GRAPH_INDEX_CACHE_MAX_ENTRIES=128`
- `TREEDB_GRAPH_INDEX_CACHE_MAX_BYTES`
- `TREEDB_WORKSPACE_WORKER_POOL_SIZE`
- `TREEDB_REPOSITORY_QUERY_POOL_SIZE`
- `TREEDB_GRAPH_WORKER_POOL_SIZE`
- `TREEDB_SNAPSHOT_WORKER_POOL_SIZE`
- `TREEDB_IMPORT_WORKER_POOL_SIZE`
- `TREEDB_REPOSITORY_QUERY_MAX_QUEUE=2000`
- `TREEDB_WORKSPACE_MUTATION_MAX_QUEUE=1000`
- `TREEDB_GRAPH_MAX_QUEUE=500`
- `TREEDB_SNAPSHOT_MAX_QUEUE=200`
- `TREEDB_IMPORT_MAX_QUEUE=100`
- `TREEDB_REPOSITORY_QUERY_QUEUE_TIMEOUT_MS=30000`
- `TREEDB_WORKSPACE_MUTATION_QUEUE_TIMEOUT_MS=30000`
- `TREEDB_GRAPH_QUEUE_TIMEOUT_MS=45000`
- `TREEDB_SNAPSHOT_QUEUE_TIMEOUT_MS=60000`
- `TREEDB_IMPORT_QUEUE_TIMEOUT_MS=60000`
- `TREEDB_HEAVY_OPERATION_EXECUTION_TIMEOUT_MS=0`

If `TREEDB_RUNTIME_MEMORY_BUDGET_MB` is set, TreeDB computes an approximate
cache byte budget from `TREEDB_CACHE_MEMORY_FRACTION` and evicts cache entries
by TTL, entry count, and approximate serialized byte size. If no memory budget
is set, caches retain the entry-count behavior.

Worker pool sizes cap expensive repository, workspace, graph, snapshot, and
import work. When all workers are active, requests enter bounded per-pool
queues instead of being rejected immediately. TreeDB returns sanitized
`server_busy` with HTTP `503` only when a queue is full, a queued request waits
past its timeout, or an optional execution timeout is reached. Performance
profiles report queue depth, wait time, and `server_busy` saturation separately
from ordinary internal failures.

Use `/api/v1/ready` to verify traffic readiness and
`/api/v1/admin/health/deep` with a `policy:read` token for protected
diagnostics. Public responses must show logical or redacted values only.

## Federation And Managed Storage

Managed repositories are addressed by canonical `repositoryName` values and
stored under `TREEDB_DATA_DIR` by TreeDB. Normal public APIs should not send
absolute repository paths.

Federation settings:

- `TREEDB_FEDERATION_ENABLED=true`
- `TREEDB_FEDERATION_NODE_ID=<node_id>`
- `TREEDB_FEDERATION_NODE_BASE_URL=<url>`
- `TREEDB_FEDERATION_PARENTS=node_a=https://node-a:4000,node_b=https://node-b:4000`
- `TREEDB_FEDERATION_AUTO_TRUST_PARENTS=true`
- `TREEDB_FEDERATION_ACCEPT_CHILD_REGISTRATION=false`
- `TREEDB_FEDERATION_CATALOG_SYNC_INTERVAL_MS=5000`
- `TREEDB_FEDERATION_CATALOG_PUSH_ENABLED=true`
- `TREEDB_FEDERATION_WRITE_PROXY_ENABLED=true`
- `TREEDB_FEDERATION_WRITE_PROXY_MAX_HOPS=1`
- `TREEDB_FEDERATION_READ_FROM_MIRRORS=true`
- `TREEDB_FEDERATION_MAX_MIRROR_STALENESS_MS=30000`
- `TREEDB_FEDERATION_LOAD_AWARE_READS=true`
- `TREEDB_FEDERATION_LOAD_AWARE_READ_PRESSURE=moderate`
- `TREEDB_FEDERATION_REMOTE_LOAD_TTL_MS=2000`
- `TREEDB_FEDERATION_SPILLOVER_MAX_ATTEMPTS=1`
- `TREEDB_FEDERATION_TRANSITIVE_DISCOVERY=false`
- `TREEDB_FEDERATION_TRANSITIVE_TRUST=false`
- `TREEDB_FEDERATION_MODE=single_node|mirror_cluster|connected_library`
- `TREEDB_REPOSITORY_STORAGE_MIGRATION=readonly`

Node identity keys default to:

- `$TREEDB_DATA_DIR/keys/node-private.pem`
- `$TREEDB_DATA_DIR/keys/node-public.pem`

If they are missing, TreeDB creates persistent local node identity material at
startup. Catalogs advertise public identity material only; they must not include
private keys, tokens, credentials, storage paths, or hidden repository content.

## Federation Access Modes

`TREEDB_FEDERATION_MODE=mirror_cluster` is for nodes operated as one cluster.
Use a shared connected-auth issuer and replicated policy/grants. Trusted peers
may receive write-proxy traffic, mirror Git data, serve fresh mirror reads, and
participate in manual mirror promotion.

`TREEDB_FEDERATION_MODE=connected_library` is for linking independently owned
libraries. Repositories remain private unless advertised. Remote owners
authorize every request, and ingress nodes may only reduce scope before sending
a delegated request. Write proxy and mirror requests are disabled by default in
this mode.

In both modes, parent configuration bootstraps discovery and catalog sync only.
Parents are not global coordinators, and children are not fully trusted unless
local policy grants trust states such as `trusted_for_query`,
`trusted_for_mirror`, or `trusted_for_write_proxy`.

Internal federation routes require node-to-node auth in addition to normal user
authorization. Node tokens are short-lived, audience-scoped, replay-checked, and
gated by peer trust state.

When load-aware reads are enabled in a mirror cluster, an ingress node may route
Git-backed repository reads to a fresh trusted mirror if the local node reaches
the configured pool pressure threshold. The current spillover set is repository
file reads, repository search, repository query, repository path listing, and
repository blob reads. Graph, context, snapshot, and artifact reads stay on the
primary unless the route points to a remote primary, because those derived
indexes and lifecycle records are not replicated by Git bundle mirror sync.
Writes remain primary-owned and never execute on mirrors unless an explicit
promotion changes the primary route.

## Managed Repository Storage

Public repository creation should use `POST /api/v1/repos` with a canonical
`repositoryName`. TreeDB derives stable repository IDs from names and stores
data under node-local managed paths. File APIs accept repository-relative paths
only.

Use `POST /api/v1/admin/repos/import-local` only for controlled imports from a
path relative to `TREEDB_DATA_DIR`. Absolute local repository paths are
compatibility-only and must not appear in public responses, audits, metrics,
logs, federation catalogs, or profiler reports.

## CI/CD Secrets

The root TreeDB workflow uses GitHub's `production` environment only for Docker
publishing after all tests pass.

Required production environment secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

The root workflow does not require npm, Node, or the ignored TypeScript SDK
package.
