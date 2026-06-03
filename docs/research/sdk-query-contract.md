# SDK Query Contract Research

## Scope

TreeDB repository query primitives map to the current `packages/ts-sdk`
read/search behavior without moving TreeSeed domain models into TreeDB. TreeDB
remains generic and Git-oriented; the SDK model registry remains responsible for
model names, field aliases, product concepts, and content directory selection.

## SDK File Search Conventions

The SDK content backend walks Markdown and MDX files under a model-specific `contentDir`. It reads files from the local content store, parses frontmatter/body, filters entries, sorts entries, and then applies `limit`.

TreeDB maps this to repository-level query parameters:

- SDK `contentDir` -> TreeDB `paths`, such as `["src/content/pages/**"]`.
- SDK local file read -> TreeDB `POST /repos/:repo_id/files/read`.
- SDK local search -> TreeDB `POST /repos/:repo_id/files/search`.
- SDK generic context queries -> TreeDB `POST /repos/:repo_id/query`.

## Content Entry Shape

The SDK builds entries with this effective shape:

```ts
{
  id: slug,
  slug,
  model: definition.name,
  title,
  path,
  body,
  frontmatter,
  createdAt,
  updatedAt
}
```

TreeDB does not return `model` or product-specific IDs. It returns generic file metadata:

```json
{
  "path": "docs/readme.md",
  "name": "readme.md",
  "extension": ".md",
  "objectId": "git_blob_sha",
  "encoding": "utf8",
  "size": 123,
  "content": "...",
  "frontmatter": {},
  "body": "...",
  "frontmatterError": null
}
```

The SDK can derive `slug`, `id`, `model`, `createdAt`, and `updatedAt` from its model registry and field bindings.

## Frontmatter Convention

The SDK parses frontmatter only when a document starts with:

```text
---
```

and contains a closing delimiter:

```text
\n---\n
```

The text between delimiters is YAML. The body is the remaining text after the closing delimiter. TreeDB follows the same delimiter convention and exposes parsed YAML as generic `frontmatter`.

Invalid YAML does not make a repository file unreadable in TreeDB. The response keeps file content available, returns empty frontmatter, and includes `frontmatterError`.

## Body And Content Fields

The SDK treats parsed Markdown/MDX body as `body`. TreeDB exposes both:

- `content`: the full decoded file content for UTF-8 reads.
- `body`: the content after frontmatter stripping for Markdown/MDX files.

For query filters, TreeDB treats `content` as an alias for `body`.

## Filter Syntax

The SDK filter shape is:

```ts
{ field: string, op: string, value: unknown }
```

Current SDK filter ops:

```text
eq
in
contains
prefix
gt
gte
lt
lte
updated_since
related_to
```

TreeDB implements the same ops over generic fields:

```text
path
name
extension
body
content
title
frontmatter.<key>
```

Unknown direct fields are treated as `frontmatter.<field>` for SDK compatibility. SDK-specific aliases remain outside TreeDB; callers should resolve aliases through the SDK model registry before sending TreeDB requests.

## Sort Syntax

The SDK sort shape is:

```ts
{ field: string, direction: "asc" | "desc" }
```

TreeDB supports the same shape over generic fields and `score`.

## Pagination Status

TreeDB supports `limit` and an opaque `cursor` for repository query APIs. SDK
callers can ignore `cursor` when they want local-mode compatibility.

TreeDB cursor format is intentionally opaque to clients; internally it is URL-safe Base64 JSON containing an offset.

## Query Result Shape

TreeDB query results are generic:

- file search results include path, object ID, score, line, column, snippet, optional frontmatter, and optional body.
- path results include path, kind, extension, object ID, mode, and size.
- section results include path, heading, level, line, and snippet.
- link results include path, label or target, line, and generic kind.
- changed-path results include path, status, base object ID, object ID, and kind.

TreeDB does not serialize TreeSeed model names, objectives, questions, proposals, decisions, agents, listings, pricing, approvals, or workflow product concepts.

## Error Types

TreeDB maps repository query errors to the existing API error shape:

```json
{
  "ok": false,
  "error": {
    "code": "permission_denied",
    "message": "Permission denied.",
    "details": {}
  }
}
```

Important query codes:

- `authentication_required`
- `permission_denied`
- `not_found`
- `unsupported_media_type`
- `validation_error`
- `internal_error`

## Path And Ref Access Semantics

TreeDB enforces authorization before ranking or serialization:

1. Resolve actor from bearer token.
2. Resolve effective scope for actor and repository.
3. Enforce required capability.
4. Enforce requested ref against scoped ref patterns.
5. Normalize and validate repository-relative paths.
6. Filter unauthorized paths before search ranking, query parsing, sorting, and pagination.

Direct reads of unauthorized paths return `403`. List/search/query endpoints omit unauthorized paths.

## Mapping Guidance

- SDK model registry handles product models and field aliases.
- TreeDB exposes generic `path`, `name`, `extension`, `body`, `content`, `frontmatter`, `sections`, `links`, and `changedPaths`.
- SDK can map model `contentDir` to TreeDB `paths`.
- SDK can map canonical fields to explicit `frontmatter.<key>` filters before calling TreeDB.
- TreeDB repository query APIs are the remote transport seam for SDK local vs.
  TreeDB mode without overloading the TreeSeed market dispatch API.
