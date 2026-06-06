# Graph, Search, and Context Productionization

Status: Productionized graph, search, and context

TreeDX hardens TreeDX graph, search, and context behavior without adding product-domain concepts. The API remains scoped to repositories, refs, paths, graph nodes, search records, context packs, and capabilities.

## Incremental Graph Refresh

`POST /api/v1/repos/:repo_id/graph/refresh` accepts optional `incremental`, `changedPaths`, `baseGraphVersion`, and `forceFull` fields.

Incremental refresh is best effort. TreeDX records the requested changed paths, checks the current graph manifest, and reports whether the refresh ran as `incremental` or fell back to `full`.

Fallback reasons:

- `missing_base_graph`
- `stale_base_graph`
- `changed_path_limit_exceeded`
- `changed_paths_empty`

Graph refresh writes a durable refresh job record. Public job status exposes logical repo/ref/path metadata only and never includes local paths or graph segment file paths.

## Search Index Segments

Search index metadata records include:

- search index manifests
- search index segment records
- index status
- index compaction status

The search index refresh path uses the same `files:search` authorization and repo/ref/path filtering as repository search. It stores logical path lists, segment IDs, source commit metadata, and content hashes. Missing index state falls back to direct repository search.

## Ranking Diagnostics

Repository file search supports opt-in diagnostics through:

```json
{
  "includeDiagnostics": true,
  "diagnosticsLevel": "summary"
}
```

Diagnostics are generated after authorization filtering. They include authorized result counts and logical score factors only. They must not include hidden paths, hidden snippets, unauthorized counts, local filesystem paths, or raw index storage paths.

## Context Modes

Context build supports:

- `brief`
- `detailed`
- `citations`
- `mixed`

Modes influence context selection and budget defaults. They do not influence authorization. Context diagnostics include requested budget, used node count, estimated tokens, truncation state, and provenance paths from the authorized result set.

## SDK Compatibility

The TypeScript SDK keeps local graph runtime behavior as the default. TreeDX graph adapter methods map server responses into SDK-compatible graph and context shapes. The SDK includes low-level client methods for graph refresh job status and search index operations.
