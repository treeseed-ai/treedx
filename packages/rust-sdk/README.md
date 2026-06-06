# TreeDB Rust SDK

`treedb-sdk` is the generic Rust SDK for TreeDB. The library crate is
`treedb_sdk`. It implements the shared `packages/sdk-spec` architecture, follows
`docs/api/openapi.yaml`, and does not encode TreeSeed product semantics.
`packages/trsd-sdk` is a downstream TreeSeed consumer/reference only.

The current `sdk-manifest.yaml` reports modules, capabilities, and test roots as
`implemented`. The SDK exposes all 113 `/api/v1` OpenAPI operations through
first-class module methods and a validated raw operation fallback.

## Install

This crate is private to the current repository baseline:

```bash
cd packages/rust-sdk
cargo test
```

Consumers use the library crate:

```rust
use treedb_sdk::{TreeDbClient, TreeDbConfig, TreeDbApiError};
```

## Configure Client

```rust
use treedb_sdk::{TreeDbClient, TreeDbConfig};

let client = TreeDbClient::new(TreeDbConfig {
    base_url: "http://localhost:4000".to_string(),
    token: Some("token".to_string()),
    ..Default::default()
});
```

The client also supports custom auth providers and injected transports for tests
or embedding.

## Authenticate

Bearer authentication uses the `Authorization: Bearer <token>` header. Tokens
may come from `TreeDbConfig.token` or an auth provider. The SDK must not place
production identity in request JSON and must not log bearer tokens.

## Basic Health Call

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
let health = client.health().await?;
let version = client.version().await?;
# Ok(())
# }
```

## Repository Query

Repository-scoped query helpers live under `client.query()`:

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
let results = client
    .query()
    .search_files("repo_demo", serde_json::json!({
        "query": "release provenance",
        "paths": ["docs/**"]
    }))
    .await?;

let file = client
    .query()
    .read_file("repo_demo", serde_json::json!({
        "ref": "refs/heads/main",
        "path": "docs/index.md"
    }))
    .await?;
# Ok(())
# }
```

## Workspace File Lifecycle

Workspace-scoped file helpers live under `client.workspaces()` and
`client.files()`:

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
let workspace = client
    .workspaces()
    .create("repo_demo", serde_json::json!({ "ref": "refs/heads/main" }))
    .await?;

client
    .files()
    .write("workspace_123", serde_json::json!({
        "path": "docs/new.md",
        "content": "# New"
    }))
    .await?;

client
    .files()
    .patch("workspace_123", serde_json::json!({
        "path": "docs/new.md",
        "patch": "..."
    }))
    .await?;

client
    .files()
    .commit("workspace_123", serde_json::json!({ "message": "Update docs" }))
    .await?;

client.workspaces().close("workspace_123", serde_json::json!({})).await?;
# Ok(())
# }
```

## Blob Upload And Download

Binary helpers use `bytes::Bytes` and do not expose string constructors for
binary upload bodies.

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
client
    .blobs()
    .upload("workspace_123", bytes::Bytes::from_static(&[1, 2, 3]), None)
    .await?;

let blob = client.blobs().download("workspace_123", None).await?;
# Ok(())
# }
```

Multipart helpers expose create, part upload, complete, and abort.

## Graph And Context Query

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
client.graph().refresh("repo_demo", serde_json::json!({})).await?;
let graph = client.graph().query("repo_demo", serde_json::json!({ "query": "MATCH ..." })).await?;
let context = client.context().build("repo_demo", serde_json::json!({ "query": "ctx docs" })).await?;
let parsed = client.context().parse("repo_demo", serde_json::json!({ "source": "ctx docs" })).await?;
# Ok(())
# }
```

## Federated Query

Federation helpers use portfolio/global TreeDB routes rather than a single
configured repository:

```rust
# async fn example(client: treedb_sdk::TreeDbClient) -> treedb_sdk::TreeDbResult<()> {
let plan = client.federation().plan(serde_json::json!({ "query": "release provenance" })).await?;
let results = client.federation().search(serde_json::json!({ "query": "release provenance" })).await?;
# Ok(())
# }
```

## Scoped Admin And Internal Modules

Full OpenAPI coverage includes sensitive scoped modules: Admin, Audit, Policy,
SearchIndex, and FederationInternal. These APIs require appropriate TreeDB
credentials and should be used carefully against production systems. They remain
generic TreeDB APIs and do not encode TreeSeed product semantics.

The raw operation fallback validates method/path pairs against generated OpenAPI
metadata before dispatch.

## Error Handling

Errors are exposed as `TreeDbApiError` with `status`, `code`, `message`,
`details`, and `payload`. Network failures use `status=0` and
`code="network_error"`.

## Pagination

`TreeDbPage` and `TreeDbCursor` preserve opaque server-owned cursor values and
`nextCursor`/`hasMore` metadata.

## Binary And Multipart

Binary payloads use `bytes::Bytes`. Multipart part numbers are passed through to
TreeDB without SDK renumbering.

## Conformance

The crate loads Phase 7 black-box scenario records and reports `NotConfigured`
until live scenario dispatch is implemented. It must not fake conformance
success.

```bash
cargo test
```

## Integration

Integration tests call a live TreeDB server only when `TREEDB_BASE_URL` is set.
Without that environment variable, they pass cleanly by reporting
not-configured behavior.

## Development Commands

```bash
node scripts/check_treedb_generated_types.mjs
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
```
