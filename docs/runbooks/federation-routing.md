# Federation Routing Runbook

TreeDB federation is a live routing fabric. Any node that receives a request can
coordinate it across the repositories in its trusted catalog. There is no
separate coordinator service; coordination is a request-time role.

## Core Routes

```text
POST /api/v1/federation/nodes/register
GET  /api/v1/federation/peers
GET  /api/v1/federation/peers/:node_id
POST /api/v1/federation/peers/:node_id/trust
POST /api/v1/federation/peers/:node_id/revoke
GET  /api/v1/federation/catalog
POST /api/v1/federation/catalog/push
POST /api/v1/federation/catalog/sync
GET  /api/v1/federation/routes
POST /api/v1/federation/query/plan
POST /api/v1/search
POST /api/v1/query
POST /api/v1/context/build
POST /api/v1/graph/query
```

Internal node-to-node routes live under `/api/v1/internal/federation/*` and are
for trusted node traffic only.

Internal federation routes are:

```text
POST /api/v1/internal/federation/proxy
POST /api/v1/internal/federation/repos/:repo_id/mirror/export
POST /api/v1/internal/federation/repos/:repo_id/mirror/import
GET  /api/v1/internal/federation/health
```

They require signed node-to-node authorization. A normal user token without a
valid node token is rejected.

## Configuration

```text
TREEDB_FEDERATION_ENABLED=true
TREEDB_FEDERATION_NODE_ID=node_a
TREEDB_FEDERATION_NODE_BASE_URL=http://node-a:4000
TREEDB_FEDERATION_PARENTS=node_parent=http://node-parent:4000
TREEDB_FEDERATION_AUTO_TRUST_PARENTS=true
TREEDB_FEDERATION_CATALOG_SYNC_INTERVAL_MS=5000
TREEDB_FEDERATION_CATALOG_PUSH_ENABLED=true
TREEDB_FEDERATION_WRITE_PROXY_ENABLED=true
TREEDB_FEDERATION_WRITE_PROXY_MAX_HOPS=1
TREEDB_FEDERATION_READ_FROM_MIRRORS=true
TREEDB_FEDERATION_MAX_MIRROR_STALENESS_MS=30000
TREEDB_FEDERATION_TRANSITIVE_DISCOVERY=false
TREEDB_FEDERATION_TRANSITIVE_TRUST=false
TREEDB_FEDERATION_MODE=single_node
TREEDB_FEDERATION_NODE_PRIVATE_KEY_PATH=/var/lib/treedb/keys/node-private.pem
TREEDB_FEDERATION_NODE_PUBLIC_KEY_PATH=/var/lib/treedb/keys/node-public.pem
```

Configured parents are trusted by the child for catalog sync. Children are not
automatically fully trusted by parents. Transitive discovery and transitive trust
are disabled unless explicitly configured.

For a three-node local topology, node A is commonly the first parent and ingress
node, node B registers through node A, and node C registers through node A and
optionally node B. This lineage helps nodes discover each other live, but every
node still applies local trust states before it imports routes or accepts
forwarded operations.

If node identity key files do not exist, TreeDB creates persistent local key
material at startup. Only public identity material is advertised in catalogs.

## Live Catalog Sync

Catalog sync runs without restarting TreeDB:

1. A node pulls catalogs from trusted parents or peers.
2. A node imports logical peer, repository, route, capacity, and mirror records.
3. Trust policy is applied locally before routes become usable.
4. Stale routes expire by TTL.
5. Local route tables are updated immediately.

Push sync sends local catalog deltas after repository, route, mirror, capacity,
or trust changes. If a route lookup misses, TreeDB can trigger a bounded
on-demand sync and retry before returning a sanitized route error.

Federation catalogs contain logical metadata only. They must not include local
filesystem paths, data directory paths, credential-bearing URLs, tokens, hidden
refs, hidden paths, snippets, request bodies, or binary payloads.

Catalog sync is live. Adding a parent, registering a node, trusting a peer,
creating a repository, changing placement, syncing a mirror, or promoting a
mirror updates route state through push, pull, or bounded on-demand sync without
restarting TreeDB.

## Routing

Reads resolve the repository route by repository ID or canonical repository
name. Local primaries execute in-process. Healthy mirrors can serve reads when
policy and freshness allow. Remote primaries or mirrors are reached through the
trusted proxy path.

Writes are primary-owned. If the receiving node is not primary and write proxy
is enabled for the trusted route, the node proxies to the primary with a node
token, original request ID, forwarding metadata, and an idempotency key. If
proxying is disabled, TreeDB returns a route-required response so the client can
target the primary directly.

Workspace requests route by workspace ID after creation. Repository reads,
path listing, search, query, graph, context, blob, snapshot, artifact, push,
sync, mirror, migration, and workspace routes all use the same route-resolution
rules. Admin storage restore, admin local import, and internal proxy requests
are intentionally not proxied.

Mutating proxied operations are idempotent at the target node. Repeating the
same idempotency key with the same method, path, body hash, and target returns
the stored response; reusing the key with a different request returns an
`idempotency_conflict` error.

## Mirrors And High Availability

Mirror assignments are separate from connected-library advertisements. A mirror
node stores data under its own data directory, imports Git data from the source,
tracks freshness, and can serve reads when the required commit is present.
Promotion changes the route table so the mirror becomes primary for future
writes. Automatic promotion is not enabled by default.

Mirror transfer uses Git data, not filesystem paths. The source exports a bundle
or equivalent repository data, the target imports it under its own
`$TREEDB_DATA_DIR/mirrors/<repositoryName>` path, verifies refs/commits, records
freshness, and pushes a catalog update. A stale mirror is not eligible for reads
when the requested ref/commit is missing or outside the configured staleness
window.

Git bundle mirrors currently serve Git-backed repository read traffic only:
repository file reads, repository path listing, repository search, repository
query, and repository blob reads. Derived-state endpoints such as graph,
context, snapshots, and artifacts remain primary-served unless the selected
route is a remote primary. Those derived indexes and lifecycle records require
their own replication path before they can safely spill over to mirrors.

## Connected-Library Access

Connected-library federation links independently owned TreeDB libraries.
Repository advertisements are private unless explicitly published to trusted
peers. Advertisements may expose selected refs, path globs, and capabilities
such as `files:search`, `graph:query`, or `context:build`.

The remote owner remains authoritative. The ingress node reduces the caller's
requested scope and sends either a permitted forwarded token or a short-lived
delegated token. The target node verifies node trust, maps the delegated actor
and scope to local grants, and authorizes again before executing. Writes and
mirror requests are denied by default in connected-library mode.

## Managed Repository Storage

Normal public APIs use canonical repository names and repository-relative file
paths. TreeDB derives storage internally:

```text
$TREEDB_DATA_DIR/repositories/<repositoryName>
$TREEDB_DATA_DIR/mirrors/<repositoryName>
```

Use `POST /api/v1/repos` to create managed repositories. Use
`POST /api/v1/admin/repos/import-local` only for controlled data-dir-relative
imports. Public responses and federation catalogs never expose those storage
paths.

## Operational Checks

1. `GET /api/v1/federation/peers` shows expected trusted peers.
2. `GET /api/v1/federation/catalog` contains logical repository advertisements.
3. `GET /api/v1/federation/routes` shows primary and mirror route records.
4. `POST /api/v1/federation/catalog/sync` refreshes trusted catalogs without a
   restart.
5. `/api/v1/ready` remains the traffic gate for each node.
6. Metrics named `treedb_federation_*` show sync, route, proxy, and mirror
   behavior.
7. A read for a repository whose primary is remote succeeds through the ingress
   node when the peer is trusted for query.
8. A write for a remote primary succeeds through proxy in mirror-cluster mode
   and is denied by default in connected-library mode.
9. A mirror read is served only when mirror freshness is within policy.

## Safety Checks

Remote and proxy routes must never expose bearer tokens, node tokens, remote
base URLs to unauthorized callers, local filesystem paths, hidden paths, hidden
snippets, hidden graph IDs, stdout/stderr, binary payloads, or raw remote
response bodies.

Use the federation profiler profiles before release-path changes:

```bash
scripts/profile-compose.sh mirror-federation
scripts/profile-compose.sh connected-library
```

Both profiles start three production-image TreeDB nodes and a profiler service.
They verify catalog convergence, route resolution, proxy behavior, mirror or
connected-library access policy, OpenAPI response schemas, semantic assertions,
and the measured load duration.
