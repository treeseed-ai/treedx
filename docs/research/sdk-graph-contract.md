# SDK Graph Contract Research

## SDK Graph Runtime Public Methods

The SDK exposes graph behavior through `ContentGraphRuntime` and `AgentSdk` helpers:

- `refresh`
- `searchFiles`
- `searchSections`
- `searchEntities`
- `getNode`
- `getNeighbors`
- `followReferences`
- `getBacklinks`
- `getRelated`
- `getSubgraph`
- `resolveSeeds`
- `queryGraph`
- `buildContextPack`
- `parseGraphDsl`
- `resolveReference`
- `explainReferenceChain`

## SDK Request/Response Shapes

Relevant SDK types include `SdkGraphRefreshRequest`, `SdkGraphSearchOptions`, `SdkGraphQueryOptions`, `SdkGraphQueryRequest`, `SdkGraphQueryResult`, `SdkContextPackRequest`, `SdkContextPack`, and `SdkGraphDslParseResult`.

Query requests support seed IDs, typed seeds, query text, graph scope, stage, scope paths, where filters, relations, view, and options. Context pack requests add `budget.maxNodes`, `budget.maxTokens`, and `budget.includeMode`.

## SDK Node And Edge Schema

SDK node types include `File`, `Section`, `Agent`, `Objective`, `Question`, `Note`, `Proposal`, `Decision`, `Knowledge`, `Book`, `Page`, `Person`, `Tag`, `Series`, `Reference`, and `Entity`.

SDK edge types include `HAS_SECTION`, `BELONGS_TO_FILE`, `PARENT_SECTION`, `CHILD_SECTION`, `NEXT_SECTION`, `PREV_SECTION`, `LINKS_TO`, `REFERENCES`, `MENTIONS`, `HAS_TAG`, `IN_SERIES`, `SAME_DIRECTORY`, `SAME_COLLECTION`, `DEFINES`, `DEFINED_BY`, `RELATES_TO`, `DEPENDS_ON`, `IMPLEMENTS`, `EXTENDS`, `SUPERSEDES`, `BELONGS_TO`, `ABOUT`, `USED_BY`, and `GENERATED_FROM`.

Important generic node fields are `id`, `nodeType`, `path`, `title`, `heading`, `text`, `tags`, `status`, `domain`, `audience`, and `data`. Edge fields are `id`, `type`, `sourceId`, `targetId`, `ownerFileId`, and `data`.

## SDK Graph DSL Behavior

The SDK ctx DSL starts with `ctx`. Seed prefixes are:

- `@id`
- `/path`
- `#tag`
- `%type`
- unprefixed query text

Supported clauses are `for`, `in`, `via`, `depth`, `where`, `limit`, `budget`, and `as`. Supported relations are `related`, `depends_on`, `implements`, `references`, `parent`, `child`, and `supersedes`.

## SDK Snapshot Storage

The current SDK stores local snapshots under `.treeseed/state/graph`. TreeDX does not expose this local path concept. TreeDX graph state lives under `$TREEDX_DATA_DIR/graph` and public API responses use logical `treedx://graph/<repo_id>/<graph_version>` locators.

## Ranking Provider Notes

The SDK supports pluggable ranking providers. TreeDX uses built-in lexical plus
graph-neighborhood scoring and exposes authorization-filtered diagnostics when
requested.

## Access Filtering Contract

The SDK scopes by model in the current local runtime. TreeDX scopes by actor, repo, ref, path, and capability. TreeDX must filter unauthorized graph segments before ranking, expansion, traversal, counting, diagnostics, and response serialization.

## TreeDX Mapping

- TreeDX file nodes map to SDK `File`.
- TreeDX heading sections map to SDK `Section`.
- Frontmatter tags map to SDK `Tag`.
- Unresolved links/imports map to SDK `Reference`.
- Directory, ref, and commit provenance nodes use SDK-compatible `Reference` nodes with generic `entityType`.

TreeDX does not encode TreeSeed product semantics. SDK integration maps generic
TreeDX graph primitives into product-specific concepts outside TreeDX.
