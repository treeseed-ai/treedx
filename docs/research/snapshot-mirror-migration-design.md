# Snapshot, Mirror, And Migration Design

## Current State

TreeDX has server-side auth, scoped capability grants, stable audit events,
federation scope reduction and execution, mirror records, mirror sync,
repository snapshots, artifact export/lifecycle, push/fetch, and placement
migration APIs.

## Snapshot Contract

Snapshots are repository/index oriented. They do not encode TreeSeed package,
release, template, market, or product semantics.

Supported snapshot kinds:

- `repository_snapshot`
- `index_snapshot`
- `graph_snapshot`
- `search_snapshot`
- `audit_export`

Snapshot manifests record repo ID, ref, resolved commit SHA, included path globs, file checksums, total bytes, optional graph version, artifact metadata, creator actor, and creation time. Public responses expose logical artifact URIs and never internal filesystem paths.

## Artifact Delivery Contract

Artifact export has two modes:

- JSON metadata by default.
- Authenticated binary download when `download=true`.

Artifacts are `artifact.tar.zst` files containing:

- `manifest.json`
- `repo/<repository-relative-path>` for included files

Artifact bytes are created by Rust store code using `tar` and `zstd`, not shell tools. API download responses use `application/zstd`, attachment content disposition, and checksum/snapshot headers.

## Mirror Sync Contract

Mirror sync is gix-backed. Local and `file://` remotes use native paths.
Authenticated HTTPS/SSH workflows use the constrained external transport when
enabled and configured with logical credential IDs. SSH requires strict
`known_hosts`.

Mirror sync persists records under TreeDX-native federation files:

- `federation/mirror_syncs.tdb`
- `federation/mirrors/<repo_id>/<target_node_id>.tdb`

Sync records include mirror ID, source/target node IDs, sanitized remote metadata, refspecs, before/after commits, updated refs, received-pack status, lag/status fields, and completion/error state. Shell Git is allowed only for tests that create fixture repositories.

## Migration Contract

Placement migration is explicit and audited. Dry-run migration persists a planned migration without changing placement. Committed migration validates the target node and, when requested, requires a synced mirror before transferring primary placement.

Committed primary transfer updates placement by:

- setting `primaryNodeId` to the target node
- adding the previous primary to mirror nodes
- removing the new primary from mirror nodes
- setting `migrationState` to `stable`

Migration records persist globally and per repository under TreeDX-native federation files.

## SDK Boundary

The TypeScript SDK receives generic snapshot, artifact, mirror sync, and migration types. TreeSeed product interpretation remains outside TreeDX. SDK clients forward bearer tokens and surface TreeDX errors as `TreeDxApiError`.

## Security Boundaries

TreeDX keeps these constraints:

- no SQL, Ecto, PostgreSQL, or SQLite
- no shell Git implementation path
- no product package/release/template semantics in TreeDX
- no internal filesystem paths in public API responses
- no artifact bytes, file contents, or credential-bearing remote URLs in audit records
