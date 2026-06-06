# TreeDX Python SDK

`treedx-sdk` is the generic Python SDK for TreeDX. It implements the shared
`packages/sdk-spec` architecture, follows `docs/api/openapi.yaml`, and does not
encode TreeSeed product semantics. `packages/trsd-sdk` is a downstream
TreeSeed consumer/reference only.

The current `sdk-manifest.yaml` reports modules, capabilities, and test roots as
`implemented`. The SDK exposes all 113 `/api/v1` OpenAPI operations through
first-class module methods and a validated raw operation fallback.

## Install

```bash
cd packages/python-sdk
python -m pip install -e ".[dev]"
```

## Configure Client

```python
from treedx_sdk import TreeDxClient, TreeDxApiError

client = TreeDxClient(
    base_url="http://localhost:4000",
    token="...",
)
```

The client also accepts an auth provider, custom transport, default headers, and
timeout settings.

## Authenticate

Bearer authentication uses the `Authorization: Bearer <token>` header. Tokens
may come from `token` or an auth provider. The SDK must not place production
identity in request JSON and must not log bearer tokens.

## Basic Health Call

```python
health = client.health()
version = client.version()
```

## Repository Query

Repository-scoped query helpers live under `client.query`:

```python
results = client.query.search_files(
    "repo_demo",
    {"query": "release provenance", "paths": ["docs/**"]},
)

file = client.query.read_file(
    "repo_demo",
    {"ref": "refs/heads/main", "path": "docs/index.md"},
)
```

## Workspace File Lifecycle

Workspace-scoped file helpers live under `client.workspaces` and `client.files`:

```python
workspace = client.workspaces.create("repo_demo", {"ref": "refs/heads/main"})

client.files.write("workspace_123", {"path": "docs/new.md", "content": "# New"})
client.files.patch("workspace_123", {"path": "docs/new.md", "patch": "..."})
client.files.commit("workspace_123", {"message": "Update docs"})
client.workspaces.close("workspace_123")
```

## Blob Upload And Download

Binary helpers preserve byte payloads and reject strings as binary input.

```python
client.blobs.upload("workspace_123", b"\x01\x02\x03")
blob = client.blobs.download("workspace_123", {"path": "asset.bin"})
```

Multipart helpers expose create, part upload, complete, and abort:

```python
upload = client.blobs.create_multipart_upload("workspace_123", {"path": "large.bin"})
client.blobs.upload_part("workspace_123", upload["uploadId"], 1, b"\x01")
client.blobs.complete_multipart_upload(
    "workspace_123",
    upload["uploadId"],
    {"parts": [{"partNumber": 1}]},
)
```

## Graph And Context Query

```python
client.graph.refresh("repo_demo")
graph = client.graph.query("repo_demo", {"query": "MATCH ..."})
context = client.context.build("repo_demo", {"query": "ctx docs"})
parsed = client.context.parse("repo_demo", {"source": "ctx docs"})
```

## Federated Query

Federation helpers use portfolio/global TreeDX routes rather than a single
configured repository:

```python
plan = client.federation.plan({"query": "release provenance"})
results = client.federation.search({"query": "release provenance"})
```

## Scoped Admin And Internal Modules

Full OpenAPI coverage includes sensitive scoped modules: Admin, Audit, Policy,
SearchIndex, and FederationInternal. These APIs require appropriate TreeDX
credentials and should be used carefully against production systems. They remain
generic TreeDX APIs and do not encode TreeSeed product semantics.

The raw operation fallback validates method/path pairs against generated OpenAPI
metadata before dispatch.

## Error Handling

Non-2xx responses and network failures raise `TreeDxApiError`. The error keeps
`status`, `code`, `message`, `details`, and `payload` available. Network
failures use `status=0` and `code="network_error"`.

```python
try:
    client.whoami()
except TreeDxApiError as error:
    print(error.status, error.code, error.message)
```

## Pagination

`TreeDxPage` and `TreeDxCursor` model opaque server-owned cursor pagination.
Helpers preserve cursor metadata and do not decode cursor internals.

## Binary And Multipart

Binary helpers accept `bytes`, `bytearray`, `memoryview`, and binary streams.
Multipart helper metadata is represented by `MultipartUpload`.

## Conformance

The conformance adapter loads Phase 7 scenario records and reports
`live or configured` until executable live dispatch is wired. It must not fake
conformance success.

```bash
python -m pytest tests/conformance
```

## Integration

Integration tests call a live TreeDX server only when `TREEDX_BASE_URL` is set.
Without that environment variable, they skip cleanly.

```bash
python -m pytest tests/integration
```

## Development Commands

```bash
python -m pip install -e ".[dev]"
python scripts/check_treedx_generated_types.py
python -m build
python -m pytest tests/conformance
python -m pytest tests/integration
python -m pytest
```
