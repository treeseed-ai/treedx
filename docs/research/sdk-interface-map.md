# SDK Interface Map

## SDK Public Exports

`packages/ts-sdk/src/index.ts` exports the primary public SDK surface. Important TreeDB-relevant exports include:

- `AgentSdk` and `ScopedAgentSdk`
- `ContentGraphRuntime`
- content storage behavior indirectly through SDK methods backed by `ContentStore`
- model registry helpers such as `buildModelRegistry`, `buildScopedModelRegistry`, and `resolveModelDefinition`
- graph and context query helpers, including DSL parsing and context query compilation
- dispatch helpers such as `findDispatchCapability`, `listSdkDispatchCapabilities`, and SDK operation execution helpers
- remote clients such as `RemoteTreeseedClient`, auth, dispatch, jobs, runner, SDK, and operations clients
- `MarketClient` and market registry/session helpers
- platform operation and runner client helpers
- repository operation helpers from `src/operations/repository-operations.ts`
- `TreeseedWorkflowSdk` and `TreeseedOperationsSdk`
- many TreeSeed market, workflow, capacity, release, and platform domain types that must remain outside TreeDB

Important package export subpaths from `packages/ts-sdk/package.json`:

- `.`
- `./sdk`
- `./operations`
- `./operations/agent-tools`
- `./api`
- `./workflow`
- `./verification`
- `./market-client`
- `./content-store`
- `./git-runtime`
- `./graph`
- `./models`

TreeDB should not replace this developer-facing SDK surface with raw TreeDB endpoints. It should provide a repository transport/backend that the SDK can select while keeping the public SDK experience stable.

## Repository Operations

`src/operations/repository-operations.ts` is TreeSeed-domain orchestration over Git and files.

The repository descriptor includes:

- `provider`
- `owner`
- `name`
- `defaultBranch`
- `cloneUrl`
- `writeMode`
- `branchName`
- `push`
- path policies
- verification commands

The operations create or update content files, commit changes, optionally run verification commands, and return navigation details such as changed paths, branch, commit SHA, and workspace path.

The file also contains TreeSeed domain collections and defaults such as `objectives`, `questions`, `notes`, `proposals`, `decisions`, and `agents`. TreeDB should support the Git, file, workspace, branch, commit, diff, and verification primitives needed by these operations, but it must not encode the meaning of those collections.

TreeDB adapter mappings:

- Replace direct workspace path access with TreeDB workspace sessions.
- Map repository descriptors to TreeDB repository registration and placement records.
- Map path policies to TreeDB path-scoped capabilities.
- Map verification commands to sandbox exec APIs.
- Preserve TreeSeed content normalization in the SDK/core layer.

## File/Blob Operations

`src/content-store.ts` is the core content-backed model implementation. It:

- lists Markdown/MDX under each model `contentDir`
- reads frontmatter and body
- searches with in-memory filters and sorts
- writes files with serialized frontmatter
- creates branch names like `agent/<model>-<slug>`
- commits through `GitRuntime`
- merges base content and `.agent-worktrees` content by latest update timestamp

TreeDB adapter seams:

- `list`, `get`, and `search` can map to TreeDB file listing, blob reads, and search/index endpoints.
- `create` and `update` can map to TreeDB workspace write plus commit endpoints.
- Frontmatter parsing, serialization, field aliasing, filtering, sorting, mutation normalization, and version checks should remain reusable pure TypeScript functions.
- The storage backend should be swappable, so the codebase does not duplicate the same content algorithms for local filesystem and remote TreeDB modes.

## Graph Operations

`src/graph.ts`, `src/graph/build.ts`, and `src/graph/query.ts` implement the current graph runtime. They:

- scan Markdown/MDX files
- parse headings, links, MDX imports, and frontmatter references
- build file, section, and entity nodes
- build authored and inferred edges
- persist graph snapshots and serialized indexes under generated graph state
- support lexical search, graph traversal, context packs, DSL parsing, reference resolution, and path explanations

TreeDB adapter seams:

- TreeDB Rust graph/search should implement generic file, section, entity, edge, rank, and context-pack primitives.
- TreeSeed model registry definitions should stay outside TreeDB and supply product-specific interpretation only at the SDK/core layer.
- Graph parsing and ranking should be implemented once around generic repository documents, with adapters for TypeScript SDK compatibility and Rust TreeDB core execution.
- TreeDB should index repository data and expose repository-scoped graph/search/context results without learning TreeSeed market semantics.

## Context/Query Operations

Context/query behavior is exposed through:

- `ContentGraphRuntime.queryGraph`
- `ContentGraphRuntime.buildContextPack`
- `ContentGraphRuntime.parseGraphDsl`
- `compileDeclarativeContextQuery`
- `declarativeContextFormatToGraphView`
- `declarativeContextPurposeToGraphStage`

TreeDB should provide generic context/query primitives over repository files, sections, entities, and edges. SDK-specific request compilers can translate TreeSeed model and context concepts into TreeDB repository graph queries.

Authorization must happen before search or graph expansion. TreeDB must reduce repo/ref/path scope first, then query only permitted indexes or segments.

## Repository/Git Operations

`src/git-runtime.ts` shells out to Git for the content mutation path:

- `git rev-parse --abbrev-ref HEAD`
- `git worktree list --porcelain`
- `git worktree add -B <branch> <path> HEAD`
- `git switch`
- `git add`
- `git commit`
- `git rev-parse HEAD`

Broader SDK Git behavior appears in workflow, workspace, release, package,
template, and verification services and tests. Areas to keep mapped include:

- `src/operations/services/git-workflow.ts`
- `src/workflow/worktrees.ts`
- `src/operations/services/git-remote-policy.ts`
- release and workspace services under `src/operations/services`
- workflow lifecycle and worktree tests under `test/utils`

TreeDB mapping:

- `currentBranch` maps to a TreeDB ref read.
- `ensureWorktree` maps to a TreeDB workspace session or materialized worktree.
- `commitFileChanges` maps to TreeDB write/patch/delete plus commit.
- Fetch, push, status, diff, workspace commit, and release-adjacent workflows map
  to TreeDB/Gitoxide/gix where practical. Product release orchestration remains
  SDK-side.
- Shell Git should be retained only as an explicit compatibility fallback with audit events and clear operation boundaries.

## Remote Dispatch Operations

`src/remote.ts`, `src/dispatch.ts`, `src/sdk-dispatch.ts`, and `src/api/sdk-routes.ts` provide the existing remote execution model.

Current behavior:

- Remote clients use JSON over HTTP.
- Auth is bearer-token based.
- Requests carry the `x-treeseed-remote-contract-version` header.
- Dispatch supports `local_only`, `remote_inline`, and `remote_job` execution classes.
- SDK operations are listed centrally in `src/sdk-dispatch.ts`.
- Dispatch capabilities are listed centrally in `src/dispatch.ts`.

The current remote API is TreeSeed market/project oriented, not TreeDB oriented. TreeDB should not overload market dispatch with repository database semantics.

TreeDB adapter seams:

- Use `TreeDbClient`, TreeDB adapters, and port classes as the separate
  repository transport.
- Keep SDK developer APIs stable and select local filesystem or remote TreeDB
  mode by configuration.
- Use explicit repo/ref/path/workspace context for TreeDB calls instead of
  `repoRoot`-only dispatch.

## Capability/Security Concepts

Current SDK auth and capability concepts are string-based and product/platform oriented:

- `src/remote.ts`: `ApiPrincipal` has `id`, `scopes`, `roles`, `permissions`, and optional metadata.
- `src/api/http.ts`: `requireScope`, `requireAuthentication`, `requireActorType`, and `requirePermission` enforce coarse API access.
- `src/api/types.ts`: `ApiAuthProvider` is the auth boundary and defines access token, service credential, trusted assertion, and session APIs.
- `src/platform-operations.ts`: platform scopes include `platform:repository:write`, `platform:runners:claim`, and operation management scopes.
- `src/dispatch.ts`: dispatch capabilities define execution class and allowed targets.

TreeDB implication:

- TreeDB needs opaque scoped capability records with tenant, repo, ref, path, workspace, and operation dimensions.
- SDK calls to TreeDB must include token plus repository/ref/path/workspace context.
- TreeDB should verify credentials and compute effective scope server-side.
- Production identity must not come from request JSON.
- String scopes may still exist as opaque claims, but TreeDB authorization must be tied to Git/repository boundaries.

## Local Filesystem Assumptions

The SDK currently assumes local filesystem access in many places:

- direct `fs/promises` reads and writes
- POSIX-ish temp and workspace paths
- `.git` directories
- `.agent-worktrees`
- `.treeseed/worktree.json`
- Markdown/MDX content discovered by recursive directory walking
- graph and index snapshots written to generated local files
- verification commands run in a local cwd

TreeDB compatibility requires a storage abstraction where these behaviors can be backed by remote file/blob/workspace APIs without duplicating parsing, filtering, graph, and model logic.

## Shell Command Assumptions

Shell usage categories in the SDK include:

- Git shell commands
- `bash -lc` command execution
- GitHub CLI commands
- Railway CLI commands
- Wrangler commands
- npm/package scripts
- script/PTY usage for workspace command tests
- verification command execution

TreeDB implication:

- TreeDB API should not expose raw shell as the primary edit path.
- `TreeDb.Exec` is capability gated, workspace scoped, audited, timeout
  bounded, and sandboxed through explicit backends.
- Shell execution should happen near the repository volume and inside a constrained workspace session.

## Auth/Token Assumptions

The current SDK supports bearer-token remote calls, device flow, token refresh, personal access tokens, service credentials, project API keys, and trusted user assertions. These are TreeSeed/API concepts today.

TreeDB should define its own verifier boundary:

- standalone/dev mode: local dev tokens and policy files under the TreeDB data directory
- connected mode: signed credentials and opaque control-plane claims
- all modes: actor identity and effective capabilities resolved before repository operations

## Repository Access Assumptions

Current SDK repository access is largely implied by local checkout access, branch conventions, path policies, and platform operation scopes. This is not sufficient for TreeDB.

TreeDB needs explicit access inputs:

- repository ID
- ref or branch pattern
- path globs
- workspace ID
- operation capability
- tenant/project/actor opaque claims

TreeDB must avoid querying all repositories and filtering unauthorized results at the end.

## TreeDB Adapter Seams

Primary seams:

1. Repository transport behind the SDK's content and workflow operations.
2. File/blob transport for list, read, write, patch, delete, and commit.
3. Workspace transport for branch/session creation and scoped materialization.
4. Graph/search transport for repository-scoped indexes and context packs.
5. Auth context propagation from SDK clients to TreeDB.
6. Capability translation from TreeSeed platform scopes into opaque TreeDB scoped grants.
7. Exec transport for verification commands and agent shell needs.

These seams are exposed through the SDK TreeDB clients, adapters, generated
OpenAPI-backed API types, and local/remote ports.

## Domain Concepts That Must Remain Outside TreeDB

These are SDK, market, core, platform, or control-plane concepts, not TreeDB concepts:

- objectives
- questions
- notes
- proposals
- decisions
- agents
- knowledge packs
- templates
- listings
- pricing/offers
- releases
- approval semantics
- workday/team inbox/capacity concepts
- platform operations and commerce workflows

TreeDB can store, update, index, search, snapshot, and query files containing these concepts, but it must not understand their product meaning.

## Breaking-Change Risks

1. Replacing SDK methods with raw TreeDB endpoints would break the developer experience.
2. Moving TreeSeed model semantics into TreeDB would violate the architecture boundary in `PLAN`.
3. Treating local path access as permanent would block remote/federated repository operation.
4. Keeping Git shell commands as the default implementation would violate the Gitoxide/gix direction.
5. Reusing market dispatch for TreeDB repository operations would blur product and repository-database boundaries.
6. Failing to add repo/ref/path/workspace authorization would create security and data leakage risks.

## Architecture Implications

### Elixir Object/Actor Model

Use Elixir/Phoenix as the actor, boundary, and lifecycle layer:

- `TreeDb.Auth`: verifies credentials and resolves actor claims.
- `TreeDb.Capabilities`: calculates effective scoped capabilities.
- `TreeDb.Repos`: owns repository records and placement lookup.
- `TreeDb.Workspaces`: supervises workspace sessions and leases.
- `TreeDb.Git`: calls Rust Git operations and constrained external transport
  only when explicitly configured.
- `TreeDb.Store`: calls Rust storage operations.
- `TreeDb.Graph`: supervises graph/index jobs.
- `TreeDb.Exec`: supervises sandboxed commands.
- `TreeDb.Audit`: records append-only audit events.
- `TreeDb.Registry`: owns node, placement, and mirror records.

Use GenServers and Supervisors for stateful lifecycles only: workspace leases, long-running jobs, mirror sync, graph refresh, and exec sessions. Keep pure policy calculations as plain modules.

### Rust Function Model

Use Rust crates as reusable function libraries with explicit input/output structs:

- `treedb_store`: encode/decode records, append logs, manifests, checksums, compaction, and recovery.
- `treedb_git`: repository open/register, refs, trees, blobs, patch, diff, commit, fetch, and push where gix supports it.
- `treedb_graph`: Markdown/MDX parsing, graph extraction, indexing, ranking, and context assembly.

Keep Rust functions deterministic and side-effect explicit:

- no hidden global state
- every function accepts data-dir, repo, or workspace context
- return typed `Result<T, TreeDbError>`
- share algorithms across Elixir API, CLI tooling, tests, and generated SDK
  contract code

### Rustler Decision

Use Rustler for stable, safe Rust functions that benefit from in-process calls, but do not claim Rustler prevents all native crashes.

Research findings:

- Rustler current Hex docs show `v0.38.0` and standard `use Rustler, otp_app: ...` loading.
- Erlang NIF docs state dirty NIFs continue running even if the calling process exits and can use dirty CPU/I/O schedulers.
- Rustler exposes dirty scheduler flags: `Normal`, `DirtyCpu`, and `DirtyIo`.
- Rust and Rustler reduce memory-safety risk for safe Rust code, but a segmentation fault in native code can still terminate the BEAM OS process.
- To prevent segmentation faults from taking down the BEAM, isolate risky native code in an external OS process or worker service invoked by ports, HTTP, or CLI, then supervise and restart it from Elixir.

Recommended split:

- Rustler NIFs for small/medium trusted operations: encoding, checksums, manifest read/write, graph query over loaded segments, path/capability matching.
- Dirty CPU NIFs for bounded CPU-heavy work.
- Dirty I/O NIFs only for bounded file operations where in-process risk is acceptable.
- External Rust worker process for packfile repair, untrusted repository parsing, long-running clone/fetch/index, and any code involving `unsafe` or complex native dependencies.

Sources:

- Rustler docs: https://hexdocs.pm/rustler/Rustler.html
- Rustler scheduler flags: https://docs.rs/rustler/latest/rustler/schedule/enum.SchedulerFlags.html
- Erlang NIF docs: https://www.erlang.org/doc/apps/erts/erl_nif.html
- gix repository docs: https://docs.rs/gix/latest/gix/struct.Repository.html
- gitoxide project: https://github.com/GitoxideLabs/gitoxide

## Initial Compatibility Issue List

1. SDK fixture submodule missing; baseline tests cannot fully run.
2. Package graph test had a self-referential retired-path assertion; this was
   corrected and the full SDK suite now passes.
3. No `typecheck` script exists.
4. SDK public API mixes generic repository/file behavior with TreeSeed market/product concepts.
5. Current content store assumes local POSIX filesystem and direct Markdown file walking.
6. Current mutations assume local Git worktrees under `.agent-worktrees`.
7. Git operations shell out broadly; TreeDB should replace common operations with gix and document shell fallback.
8. Current auth scopes are string-based and not repo/ref/path/workspace scoped enough for TreeDB.
9. Existing remote dispatch is market/project oriented; TreeDB needs a separate repository transport seam.
10. Graph indexing is reusable but currently tied to local file scanning and generated local snapshots.
