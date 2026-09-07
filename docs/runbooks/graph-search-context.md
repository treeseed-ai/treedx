# Graph, Search, and Context Runbook

Status: Productionized graph, search, and context

## Refresh A Graph

Use full refresh when there is no trusted base graph:

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"paths":["docs/**"],"forceFull":true}' \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/graph/refresh"
```

Use best-effort incremental refresh when changed paths are known:

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"incremental":true,"baseGraphVersion":"graph_...","changedPaths":["docs/readme.md"]}' \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/graph/refresh"
```

If the response contains `fallbackReason`, TreeDX performed a full refresh. This is safe and expected when the base graph is stale, missing, or too many changed paths were supplied.

## Query By File Path

File paths are the default seed selector; node IDs remain explicit advanced selectors.
Repository queries also default to path selection: `{"query":"knowledge/**/setup?"}`
selects matching files. Full-text searches use `type: "text"` or the search endpoint.
Send `{"paths":["knowledge/**/setup?"],"ref":"<exact-ref>","options":{"depth":0}}`
to `/api/v1/repos/<repo-id>/graph/query`. A seed such as
`{"value":"knowledge/providers"}` also defaults to a path.

Extensions are optional for both names and glob patterns. `*` matches within one
path segment, `?` matches one character, and `**/` spans zero or more directories.
Thus `knowledge/**/setup?` matches `knowledge/setup1.md` and
`knowledge/nested/setup2.yaml`. Explicit extensions such as `**/*.md` restrict the
format. Recognized content formats are MDX, Markdown (`md`, `markdown`), JSON,
YAML (`yaml`, `yml`), and TOML. Results retain actual source paths and resolved refs.

An exact existing filename wins. A single extensionless name with multiple matches
returns a conflict; use a glob to request multiple formats intentionally. Graph
expansion uses only authorized indexed paths, is capped at 1,000 paths, and does
not change graph result limits. Missing matches return no seed results. Repository
path filters use the same extensionless glob semantics. Writes still require exact paths.

## Check Refresh Job Status

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/graph/refresh-jobs/$JOB_ID"
```

The response contains logical repo/ref/path metadata only. It must not expose local graph segment paths.

## Refresh Search Index Metadata

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"paths":["docs/**"]}' \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/search/index/refresh"
```

Search index refresh requires `files:search` and applies path scope before writing metadata.

## Check Search Index Status

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/search/index/status"
```

If `ready` is false, repository search falls back to direct scanning.

## Compact Search Index Metadata

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"planOnly":true}' \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/search/index/compact"
```

Compaction status is logical metadata. It does not expose data directory paths.

## Build Context With A Mode

```bash
curl -sS -H "authorization: Bearer $TOKEN" \
  -H "content-type: application/json" \
  -d '{"query":"release","mode":"citations","budget":{"maxNodes":8,"maxTokens":2000}}' \
  "$TREEDX_URL/api/v1/repos/$REPO_ID/context/build"
```

Available modes are `brief`, `detailed`, `citations`, and `mixed`. Modes affect selection and diagnostics only; authorization is unchanged.
