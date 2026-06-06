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
  -d '{"dryRun":true}' \
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
