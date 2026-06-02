# Snapshot, Mirror, And Migration Design

## Current Phase 8 State

TreeDB has server-side auth, scoped capability grants, stable audit events, and planner-only federation access reduction. Mirror records exist in the registry, but Phase 8 does not perform network sync. Federation planning intentionally does not execute global search/query. There is no repository snapshot, artifact export, or placement migration API before Phase 9.

## Snapshot Contract

Phase 9 snapshots are repository/index oriented. They do not encode TreeSeed package, release, template, market, or product semantics.

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

Mirror sync is gix-backed. Phase 9 supports local file remotes and HTTP(S) where enabled by gix features. SSH remotes return a structured `unsupported_transport` error unless a future build enables and validates SSH transport.

Mirror sync persists records under TreeDB-native federation files:

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

Migration records persist globally and per repository under TreeDB-native federation files.

## SDK Boundary

The TypeScript SDK receives generic snapshot, artifact, mirror sync, and migration types. TreeSeed product interpretation remains outside TreeDB. SDK clients forward bearer tokens and surface TreeDB errors as `TreeDbApiError`.

## Security Boundaries

Phase 9 keeps these constraints:

- no SQL, Ecto, PostgreSQL, or SQLite
- no shell Git implementation path
- no product package/release/template semantics in TreeDB
- no internal filesystem paths in public API responses
- no artifact bytes, file contents, or credential-bearing remote URLs in audit records
