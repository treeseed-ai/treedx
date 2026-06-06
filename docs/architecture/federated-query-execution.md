# Federated Query Execution

TreeDX federation combines connected-library discovery with mirrored
high-availability routing. Every node can act as ingress, coordinator, primary,
mirror, connected-library node, and capacity provider depending on the request
and the routes in its trusted catalog.

## Trust And Discovery

Discovery is not trust. Nodes may discover peers through configured parents,
catalog sync, or explicit registration, but each node applies its own trust
policy before importing routes or forwarding requests.

Trust states are scoped:

```text
discovered
registered
trusted_for_catalog
trusted_for_query
trusted_for_mirror
trusted_for_write_proxy
trusted_for_admin
blocked
```

Configured parents are trusted by a child for catalog sync. Parents do not
automatically grant full trust to children. Transitive discovery and transitive
trust are off by default.

Parent lineage is the bootstrap mechanism, not a permanent coordinator model.
For example, in a three-node topology node B may start with node A as a parent,
and node C may start with node A and node B as parents. B and C can learn about
each other through live catalog sync, but neither node treats discovered peers
as trusted for query, mirror, or write-proxy operations until local trust policy
grants those states. Any node can later receive a client request and coordinate
it using the trusted catalog it has learned.

Node-to-node routes use signed short-lived node tokens. Internal requests are
accepted only when the peer is known, not blocked, the token audience matches
the receiving node, the token is unexpired and not replayed, and the peer's
trust state allows the requested operation. Normal user bearer tokens alone are
not sufficient for `/api/v1/internal/federation/*` routes.

## Catalog And Route Model

Federation catalogs advertise logical metadata:

- node ID and base URL
- public node identity material
- repository ID and canonical repository name
- owner, primary, and mirror node IDs
- refs, path globs, capabilities, and visibility
- capacity and mirror freshness

Catalogs never include local storage paths, data directory paths, credential
URLs, tokens, hidden refs, hidden paths, snippets, request bodies, or binary
payloads.

Routes map a repository to a primary and zero or more mirrors. Reads may use a
fresh mirror when policy allows. Writes always route to the current primary.
Mirror promotion updates the route table, after which future writes route to the
promoted node.

Workspace routes are tracked separately from repository routes. Once a
workspace is created on a primary, subsequent workspace file, blob, status,
diff, commit, close, and exec requests resolve by workspace ID first. This lets
an ingress node transparently forward follow-up workspace operations to the node
that owns the workspace state.

## Request Flow

Global search, query, context, and graph routes still start with scope
reduction. The ingress node resolves the caller's effective repository, ref,
path, and capability scope before executing locally or proxying remotely.

For reads:

1. Resolve the repository route by ID or canonical name.
2. Execute locally if the node is primary.
3. Execute locally if the node is a fresh eligible mirror.
4. Proxy to a trusted primary or mirror.
5. Trigger one bounded on-demand catalog sync on route miss.
6. Return a sanitized route error if no trusted route exists.

For writes:

1. Resolve the primary route.
2. Execute locally if this node is primary.
3. Proxy to the primary when same-cluster trust and write proxy are enabled.
4. Return a write-route-required response when proxying is disabled.

Proxied mutating requests require idempotency keys. If the client does not
provide one, ingress derives it from the original request ID, method, path, body
hash, and target node.

Proxying preserves the public API contract. The ingress node forwards a reduced
request plus node authorization, original request metadata, and either the
original user token where policy permits it or a scoped delegated token. The
target node independently authorizes the operation before executing it. Public
responses may include optional logical route metadata, but they must not expose
node tokens, delegated tokens, private peer data, storage paths, hidden paths,
raw snippets, stdout/stderr, or binary payloads.

Repository, workspace, blob, graph, search, context, snapshot, artifact, mirror,
push, sync, and migration routes are federation-aware. Admin storage restore,
admin local import, and the internal proxy route itself are not proxied.

## Connected Libraries And HA Mirrors

Connected-library mode keeps the remote owner authoritative. Repositories are
private unless advertised. Write proxy and mirror requests are disabled by
default unless the owner explicitly grants them.

Mirrored HA mode is for same-cluster operation. Nodes share or replicate auth and
policy configuration, mirrors sync Git data instead of filesystem paths, and a
promotion action changes the primary placement. Automatic promotion is deferred
until operators enable a clear policy.

The two modes share the same catalog, route, and proxy machinery but use
different access assumptions:

- In mirror-cluster mode, nodes are operated as one administrative trust domain.
  They normally share connected auth issuers and replicated grants. Write proxy
  can be enabled for trusted peers, and fresh mirrors can serve reads.
- In connected-library mode, each owner remains authoritative for its own
  repositories. Advertisements expose only selected refs, path globs, and
  capabilities. Ingress nodes reduce scope before forwarding, and the remote
  owner enforces delegated scope again. Write proxy and mirroring are denied by
  default.

## Managed Repository Storage

Repository names are canonical lowercase identifiers and unique in the trusted
catalog. Repository IDs are deterministic from the canonical name and independent
of the data directory.

TreeDX stores managed repositories in node-local paths derived internally:

```text
$TREEDX_DATA_DIR/repositories/<repositoryName>
$TREEDX_DATA_DIR/mirrors/<repositoryName>
```

Public APIs use repository IDs/names and repository-relative file paths. Absolute
repository paths are compatibility-only internal setup data and are not included
in public responses, audit payloads, metrics, logs, profiler reports, or
federation catalogs.

`POST /api/v1/repos` is the preferred public creation route. Compatibility
registration remains available for managed repositories, and admin local import
accepts data-dir-relative import sources only. This keeps repository access
stable when nodes use different data directories and allows catalogs to sync
logical repository identity without leaking filesystem topology.
