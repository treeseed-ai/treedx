# TreeDX Elixir SDK

`treedx_sdk` is the generic Elixir SDK for TreeDX. The public namespace is
`TreeDxSdk`. It implements the shared `packages/sdk-spec` architecture, follows
`docs/api/openapi.yaml`, and does not encode TreeSeed product semantics.
`packages/trsd-sdk` is a downstream TreeSeed consumer/reference only.

The current `sdk-manifest.yaml` reports modules, capabilities, and test roots as
`implemented`. The SDK exposes all 113 `/api/v1` OpenAPI operations through
first-class module methods and a validated raw operation fallback.

## Install

This package is private to the current repository baseline:

```bash
cd packages/elixir-sdk
mix deps.get
```

## Configure Client

```elixir
client =
  TreeDxSdk.Client.new(
    base_url: "http://localhost:4000",
    token: System.get_env("TREEDX_TOKEN")
  )
```

The client also accepts an auth provider, injected transport, default headers,
and timeout settings.

## Authenticate

Bearer authentication uses the `Authorization: Bearer <token>` header. Tokens
may come from `:token` or an auth provider. The SDK must not place production
identity in request JSON and must not log bearer tokens.

## Basic Health Call

```elixir
{:ok, health} = TreeDxSdk.health(client)
{:ok, version} = TreeDxSdk.version(client)
```

## Repository Query

Repository-scoped query helpers live under `TreeDxSdk.Query`:

```elixir
{:ok, results} =
  TreeDxSdk.Query.search_files(client, "repo_demo", %{
    query: "release provenance",
    paths: ["docs/**"]
  })

{:ok, file} =
  TreeDxSdk.Query.read_file(client, "repo_demo", %{
    ref: "refs/heads/main",
    path: "docs/index.md"
  })
```

## Workspace File Lifecycle

Workspace-scoped file helpers live under `TreeDxSdk.Workspaces` and
`TreeDxSdk.Files`:

```elixir
{:ok, workspace} = TreeDxSdk.Workspaces.create(client, "repo_demo", %{ref: "refs/heads/main"})

{:ok, _} = TreeDxSdk.Files.write(client, "workspace_123", %{path: "docs/new.md", content: "# New"})
{:ok, _} = TreeDxSdk.Files.patch(client, "workspace_123", %{path: "docs/new.md", patch: "..."})
{:ok, _} = TreeDxSdk.Files.commit(client, "workspace_123", %{message: "Update docs"})
{:ok, _} = TreeDxSdk.Workspaces.close(client, "workspace_123")
```

## Blob Upload And Download

Binary helpers accept binaries and iodata and do not treat JSON strings as
upload bodies.

```elixir
{:ok, _} = TreeDxSdk.Blobs.upload(client, "workspace_123", <<1, 2, 3>>)
{:ok, blob} = TreeDxSdk.Blobs.download(client, "workspace_123", %{path: "asset.bin"})
```

Multipart helpers expose create, part upload, complete, and abort.

## Graph And Context Query

```elixir
{:ok, _} = TreeDxSdk.Graph.refresh(client, "repo_demo")
{:ok, graph} = TreeDxSdk.Graph.query(client, "repo_demo", %{query: "MATCH ..."})
{:ok, context} = TreeDxSdk.Context.build(client, "repo_demo", %{query: "ctx docs"})
{:ok, parsed} = TreeDxSdk.Context.parse(client, "repo_demo", %{source: "ctx docs"})
```

## Federated Query

Federation helpers use portfolio/global TreeDX routes rather than a single
configured repository:

```elixir
{:ok, plan} = TreeDxSdk.Federation.plan(client, %{query: "release provenance"})
{:ok, results} = TreeDxSdk.Federation.search(client, %{query: "release provenance"})
```

## Scoped Admin And Internal Modules

Full OpenAPI coverage includes sensitive scoped modules: Admin, Audit, Policy,
SearchIndex, and FederationInternal. These APIs require appropriate TreeDX
credentials and should be used carefully against production systems. They remain
generic TreeDX APIs and do not encode TreeSeed product semantics.

The raw operation fallback validates method/path pairs against generated OpenAPI
metadata before dispatch.

## Error Handling

Calls return `{:ok, value}` or `{:error, %TreeDxSdk.Error{}}`. The error keeps
`status`, `code`, `message`, `details`, and `payload`. Network failures use
`status: 0` and `code: "network_error"`.

## Pagination

`TreeDxSdk.Pagination` preserves opaque server-owned cursor values and accepts
server camelCase keys such as `nextCursor` and `hasMore`.

## Binary And Multipart

Binary helpers accept Elixir binaries and iodata. Multipart upload maps use
`upload_id` and `completed_parts` while preserving TreeDX part numbers.

## Conformance

The package loads Phase 7 black-box scenario records and reports
`:live or configured` until live scenario dispatch is implemented. It must not fake
conformance success.

```bash
mix test test/conformance
```

## Integration

Integration tests call a live TreeDX server only when `TREEDX_BASE_URL` is set.
Without that environment variable, they pass cleanly by reporting
not-configured behavior.

```bash
mix test test/integration
```

## Development Commands

```bash
mix deps.get
mix run scripts/check_treedx_generated_types.exs
mix format --check-formatted
mix test test/conformance
mix test test/integration
mix test
```
