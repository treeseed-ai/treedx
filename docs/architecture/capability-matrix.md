# TreeDB Capability Matrix

Status: Stage 0 baseline  
Source of truth: `apps/api/lib/treedb_web/router.ex`  
Scope: Public `/api/v1` HTTP routes

This matrix freezes the current route inventory and the intended capability
contract for Stage 1 hardening. `public` means the route may be called without a
principal. `auth` means a principal is required but no narrower capability is
required by the route itself.

| Method | Path | Controller action | Required capability | Repo | Ref | Path | Workspace | Public | Audit event | Stage 1 gap |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| GET | `/api/v1/health` | `HealthController.health` | public | no | no | no | no | yes | none | none |
| GET | `/api/v1/version` | `HealthController.version` | public | no | no | no | no | yes | none | none |
| GET | `/api/v1/auth/whoami` | `AuthController.whoami` | public/auth optional | no | no | no | no | yes | none | none |
| GET | `/api/v1/auth/mode` | `AuthController.mode` | public | no | no | no | no | yes | none | none |
| POST | `/api/v1/auth/dev-token` | `AuthController.dev_token` | public in dev only | no | no | no | no | yes | `auth.dev_token_created` | production mode must fail closed |
| GET | `/api/v1/policy/effective-scope` | `PolicyController.effective_scope` | `policy:read` | optional | no | no | no | dev optional | `policy.effective_scope_resolved` | remove dev default from production paths |
| POST | `/api/v1/policy/refresh` | `PolicyController.refresh` | `policy:write` | no | no | no | no | no | `policy.refreshed` | implement revocation payload |
| GET | `/api/v1/policy/capabilities` | `CapabilityController.capabilities` | `policy:read` | no | no | no | no | no | none | none |
| GET | `/api/v1/policy/grants` | `CapabilityController.grants` | `policy:read` | optional | no | no | no | no | none | none |
| POST | `/api/v1/policy/grants` | `CapabilityController.put_grant` | `policy:write` | optional | no | no | no | no | `policy.grant.updated` | add revocation fields |
| GET | `/api/v1/audit/events` | `AuditController.events` | `audit:read` | optional | no | no | no | no | none | ensure redaction |
| POST | `/api/v1/federation/query/plan` | `FederationController.plan_query` | `query:federated` | yes | yes | yes | no | no | federation planning audit | leakage tests |
| GET | `/api/v1/node` | `NodeController.show` | `registry:read` | no | no | no | no | no | none | none |
| GET | `/api/v1/registry/nodes` | `RegistryController.nodes` | `registry:read` | no | no | no | no | no | none | none |
| GET | `/api/v1/registry/repos/:repo_id/placement` | `RegistryController.placement` | `registry:read` | yes | no | no | no | no | none | none |
| POST | `/api/v1/registry/repos/:repo_id/placement` | `RegistryController.put_placement` | `registry:write` | yes | no | no | no | no | placement write audit | none |
| POST | `/api/v1/repos/register` | `RepoController.register` | `repos:write` | yes | no | no | no | no | repository register audit | response hygiene |
| GET | `/api/v1/repos` | `RepoController.index` | `repos:read` | yes | no | no | no | no | none | filter hidden repos before serialization |
| GET | `/api/v1/repos/:repo_id` | `RepoController.show` | `repos:read` | yes | no | no | no | no | none | response hygiene |
| GET | `/api/v1/repos/:repo_id/status` | `RepoController.status` | `repos:read` | yes | no | no | no | no | none | response hygiene |
| GET | `/api/v1/repos/:repo_id/refs` | `RepoController.refs` | `git:read` | yes | yes | no | no | no | none | ref filtering |
| GET | `/api/v1/repos/:repo_id/remotes` | `RepoController.remotes` | `remotes:read` | yes | no | no | no | no | none | credential scrubbing |
| POST | `/api/v1/repos/:repo_id/sync` | `RepoController.sync` | `git:fetch` | yes | optional | no | no | no | sync audit | credential scrubbing |
| POST | `/api/v1/repos/:repo_id/files/search` | `RepoQueryController.search` | `files:search` | yes | yes | yes | no | no | query audit | leakage tests |
| POST | `/api/v1/repos/:repo_id/files/read` | `RepoQueryController.read` | `files:read` | yes | yes | yes | no | no | file read audit | leakage tests |
| POST | `/api/v1/repos/:repo_id/blobs/read` | `BlobController.read_repo` | `files:read` | yes | yes | yes | no | no | `blob.read` | Stage 2 binary-safe base64 read |
| POST | `/api/v1/repos/:repo_id/paths/list` | `RepoQueryController.paths` | `files:read` | yes | yes | yes | no | no | path list audit | hide unauthorized paths |
| POST | `/api/v1/repos/:repo_id/query` | `RepoQueryController.query` | `files:search` | yes | yes | yes | no | no | query audit | rank only authorized results |
| POST | `/api/v1/repos/:repo_id/graph/refresh` | `GraphController.refresh` | `graph:refresh` | yes | yes | yes | no | no | graph refresh audit | none |
| POST | `/api/v1/repos/:repo_id/graph/query` | `GraphController.query` | `graph:query` | yes | yes | yes | no | no | graph query audit | leakage tests |
| POST | `/api/v1/repos/:repo_id/graph/search-files` | `GraphController.search_files` | `graph:query` | yes | yes | yes | no | no | graph query audit | leakage tests |
| POST | `/api/v1/repos/:repo_id/graph/search-sections` | `GraphController.search_sections` | `graph:query` | yes | yes | yes | no | no | graph query audit | leakage tests |
| POST | `/api/v1/repos/:repo_id/graph/search-entities` | `GraphController.search_entities` | `graph:query` | yes | yes | yes | no | no | graph query audit | leakage tests |
| GET | `/api/v1/repos/:repo_id/graph/nodes/:node_id` | `GraphController.node` | `graph:query` | yes | yes | yes | no | no | graph query audit | hidden node checks |
| POST | `/api/v1/repos/:repo_id/graph/related` | `GraphController.related` | `graph:query` | yes | yes | yes | no | no | graph query audit | hidden edge checks |
| POST | `/api/v1/repos/:repo_id/graph/subgraph` | `GraphController.subgraph` | `graph:query` | yes | yes | yes | no | no | graph query audit | hidden edge checks |
| POST | `/api/v1/repos/:repo_id/context/build` | `ContextController.build` | `graph:query` | yes | yes | yes | no | no | context build audit | snippets must be authorized |
| POST | `/api/v1/repos/:repo_id/context/parse-ctx` | `ContextController.parse_ctx` | `graph:query` | yes | optional | optional | no | no | none | none |
| POST | `/api/v1/repos/:repo_id/snapshots/build` | `SnapshotController.build` | `snapshot:build` | yes | yes | yes | no | no | snapshot build audit | hide excluded paths |
| GET | `/api/v1/repos/:repo_id/snapshots/:snapshot_id` | `SnapshotController.show` | `snapshot:build` | yes | no | no | no | no | none | hide file lists by policy |
| POST | `/api/v1/repos/:repo_id/artifacts/export` | `SnapshotController.export` | `artifact:export` | yes | no | no | no | no | artifact export audit | no internal paths |
| POST | `/api/v1/repos/:repo_id/workspaces` | `RepoController.create_workspace` | `workspace:create` plus repo mode capability | yes | yes | yes | no | no | `workspace.created` | persist policy hash |
| GET | `/api/v1/repos/:repo_id/mirrors` | `RegistryController.mirrors` | `mirror:read` | yes | optional | no | no | no | none | credential hygiene |
| POST | `/api/v1/repos/:repo_id/mirrors` | `RegistryController.put_mirror` | `mirror:write` | yes | optional | no | no | no | mirror write audit | credential hygiene |
| POST | `/api/v1/repos/:repo_id/mirrors/:mirror_id/sync` | `RegistryController.sync_mirror` | `mirror:write`, `git:fetch` | yes | optional | no | no | no | mirror sync audit | credential hygiene |
| POST | `/api/v1/repos/:repo_id/migrations` | `MigrationController.create` | `migration:write` | yes | no | no | no | no | migration audit | none |
| GET | `/api/v1/repos/:repo_id/migrations/:migration_id` | `MigrationController.show` | `migration:read` | yes | no | no | no | no | none | none |
| GET | `/api/v1/workspaces/:workspace_id` | `WorkspaceController.show` | same actor | via workspace | via workspace | via workspace | yes | no | none | policy hash check |
| POST | `/api/v1/workspaces/:workspace_id/close` | `WorkspaceController.close` | same actor | via workspace | via workspace | via workspace | yes | no | `workspace.closed` | policy hash check |
| GET | `/api/v1/workspaces/:workspace_id/tree` | `FileController.tree` | `files:read` | via workspace | via workspace | yes | yes | no | `file.tree_listed` | policy hash check |
| GET | `/api/v1/workspaces/:workspace_id/files` | `FileController.read` | `files:read` | via workspace | via workspace | yes | yes | no | `file.read` | policy hash check |
| PUT | `/api/v1/workspaces/:workspace_id/files` | `FileController.write` | `files:write` | via workspace | via workspace | yes | yes | no | `file.written` | policy hash check |
| PATCH | `/api/v1/workspaces/:workspace_id/files` | `FileController.patch` | `files:write` | via workspace | via workspace | yes | yes | no | `file.patched` | policy hash check |
| DELETE | `/api/v1/workspaces/:workspace_id/files` | `FileController.delete` | `files:delete` | via workspace | via workspace | yes | yes | no | `file.deleted` | policy hash check |
| POST | `/api/v1/workspaces/:workspace_id/blobs/write` | `BlobController.write` | `files:write` | via workspace | via workspace | yes | yes | no | `blob.written` | Stage 2 binary-safe overlay |
| POST | `/api/v1/workspaces/:workspace_id/blobs/delete` | `BlobController.delete` | `files:delete` | via workspace | via workspace | yes | yes | no | `blob.deleted` | Stage 2 binary-safe overlay |
| GET | `/api/v1/workspaces/:workspace_id/blobs/download` | `BlobController.download` | `files:read` | via workspace | via workspace | yes | yes | no | `blob.downloaded` | Stage 2 raw byte download |
| PUT | `/api/v1/workspaces/:workspace_id/blobs/upload` | `BlobController.upload` | `files:write` | via workspace | via workspace | yes | yes | no | `blob.uploaded` | Stage 2 raw byte upload |
| POST | `/api/v1/workspaces/:workspace_id/search` | `FileController.search` | `files:search` | via workspace | via workspace | yes | yes | no | `file.searched` | policy hash check |
| GET | `/api/v1/workspaces/:workspace_id/status` | `FileController.status` | `files:read` | via workspace | via workspace | yes | yes | no | `workspace.status_viewed` | policy hash check |
| GET | `/api/v1/workspaces/:workspace_id/diff` | `FileController.diff` | `git:diff` | via workspace | via workspace | yes | yes | no | `workspace.diff_viewed` | policy hash check |
| POST | `/api/v1/workspaces/:workspace_id/commit` | `FileController.commit` | `git:commit` | via workspace | via workspace | yes | yes | no | `workspace.committed` | policy hash check |
| POST | `/api/v1/workspaces/:workspace_id/exec` | `ExecController.exec` | workspace exec capability | via workspace | via workspace | yes | yes | no | exec audit | sandbox hardening later |

Stage 1 adds:

- `GET /api/v1/admin/workspaces/quarantined`
- `GET /api/v1/admin/storage/health`
- `POST /api/v1/admin/storage/check`
- `POST /api/v1/admin/storage/recover`

Stage 3 adds:

| Method | Path | Controller action | Required capability | Repo | Ref | Path | Workspace | Public | Audit event | Stage 3 note |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| POST | `/api/v1/repos/:repo_id/push` | `PushController.push` | `git:push` | yes | source and destination refspec refs | no | no | no | `git.push.started`, `git.push.completed`, `git.push.failed` | explicit non-wildcard refspecs only; remote URLs are sanitized |
| POST | `/api/v1/repos/:repo_id/sync` | `RepoController.sync` | `git:fetch` | yes | optional fetch refs | no | no | no | `git.fetch.completed` | request body accepts remote name/url/refspecs/dryRun |
| POST | `/api/v1/repos/:repo_id/mirrors/:mirror_id/health` | `RegistryController.mirror_health` | `mirror:read`, `registry:read` | yes | no | no | no | no | `mirror.health_checked` | reports logical health only |
| POST | `/api/v1/repos/:repo_id/mirrors/:mirror_id/promote` | `RegistryController.promote_mirror` | `migration:read` for dry-run, `migration:write` for apply | yes | no | no | no | no | `mirror.promotion_planned`, `mirror.promoted` | promotion requires synced mirror when requested |
| POST | `/api/v1/admin/storage/compact` | `AdminStorageController.compact` | `policy:write` | no | no | no | no | no | `storage.compacted` | compacts latest-record logs, never audit logs |
| POST | `/api/v1/admin/storage/backup` | `AdminStorageController.backup` | `policy:read` | no | no | no | no | no | `storage.backup_created` | returns logical backup URI only |

Stage 3 also hardens `POST /api/v1/workspaces/:workspace_id/exec` with
`TREEDB_EXEC_BACKEND`, sandbox metadata, network denial by default, and
binary-safe `write_limited` overlay persistence.

Stage 4 adds:

| Method | Path | Controller action | Required capability | Repo | Ref | Path | Workspace | Public | Audit event | Stage 4 note |
|---|---|---|---|---:|---:|---:|---:|---:|---|---|
| POST | `/api/v1/search` | `GlobalQueryController.search` | `query:federated`, `files:search` | yes | yes | yes | no | no | `federated.search.started`, `federated.search.completed`, `federated.search.partial` | executes only reduced authorized repository scopes |
| POST | `/api/v1/query` | `GlobalQueryController.query` | `query:federated` plus query-specific file/git capability | yes | yes | yes | no | no | `federated.query.started`, `federated.query.completed`, `federated.query.partial` | `text`/`combined` use `files:search`; `changed_path` uses `git:diff`; others use `files:read` |
| POST | `/api/v1/context/build` | `GlobalQueryController.context` | `query:federated`, `graph:query` | yes | yes | yes | no | no | `federated.context.started`, `federated.context.completed`, `federated.context.partial` | merges authorized context packs and applies a global budget |
| POST | `/api/v1/graph/query` | `GlobalQueryController.graph` | `query:federated`, `graph:query` | yes | yes | yes | no | no | `federated.graph.started`, `federated.graph.completed`, `federated.graph.partial` | qualifies cross-repo graph IDs with `treedb://repo/...` |
