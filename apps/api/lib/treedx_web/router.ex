defmodule TreeDxWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(TreeDxWeb.AuthPlug)
  end

  scope "/", TreeDxWeb do
    get("/metrics", MetricsController, :prometheus)
  end

  scope "/api/v1", TreeDxWeb do
    pipe_through(:api)

    get("/health", HealthController, :health)
    get("/ready", HealthController, :ready)
    get("/health/deep", HealthController, :deep)
    get("/version", HealthController, :version)
    get("/metrics", MetricsController, :json)

    get("/auth/whoami", AuthController, :whoami)
    get("/auth/mode", AuthController, :mode)
    post("/auth/dev-token", AuthController, :dev_token)
    get("/policy/effective-scope", PolicyController, :effective_scope)
    post("/policy/refresh", PolicyController, :refresh)
    get("/policy/capabilities", CapabilityController, :capabilities)
    get("/policy/grants", CapabilityController, :grants)
    post("/policy/grants", CapabilityController, :put_grant)
    get("/audit/events", AuditController, :events)
    post("/federation/query/plan", FederationController, :plan_query)
    post("/federation/nodes/register", FederationNodeController, :register)
    get("/federation/peers", FederationNodeController, :index)
    get("/federation/peers/:node_id", FederationNodeController, :show)
    post("/federation/peers/:node_id/trust", FederationNodeController, :trust)
    post("/federation/peers/:node_id/revoke", FederationNodeController, :revoke)
    get("/federation/catalog", FederationCatalogController, :catalog)
    post("/federation/catalog/push", FederationCatalogController, :push)
    post("/federation/catalog/sync", FederationCatalogController, :sync)
    get("/federation/routes", FederationCatalogController, :routes)
    post("/search", GlobalQueryController, :search)
    post("/query", GlobalQueryController, :query)
    post("/context/build", GlobalQueryController, :context)
    post("/graph/query", GlobalQueryController, :graph)
    get("/admin/workspaces/quarantined", AdminWorkspaceController, :quarantined)
    get("/admin/health/deep", HealthController, :admin_deep)
    get("/admin/storage/health", AdminStorageController, :health)
    post("/admin/storage/check", AdminStorageController, :check)
    post("/admin/storage/recover", AdminStorageController, :recover)
    post("/admin/storage/compact", AdminStorageController, :compact)
    post("/admin/storage/backup", AdminStorageController, :backup)
    get("/admin/storage/migrations", AdminStorageController, :migrations)
    post("/admin/storage/migrations/plan", AdminStorageController, :plan_migration)
    post("/admin/storage/migrations/apply", AdminStorageController, :apply_migration)
    post("/admin/storage/migrations/rollback", AdminStorageController, :rollback_migration)
    post("/admin/storage/restore/verify", AdminStorageController, :verify_restore)
    post("/admin/storage/restore", AdminStorageController, :restore)
    post("/admin/artifacts/cleanup", ArtifactController, :cleanup)
    post("/admin/repos/import-local", RepoController, :import_local)

    get("/node", NodeController, :show)
    get("/registry/nodes", RegistryController, :nodes)
    get("/registry/repos/:repo_id/placement", RegistryController, :placement)
    post("/registry/repos/:repo_id/placement", RegistryController, :put_placement)

    post("/repos", RepoController, :create)
    post("/repos/register", RepoController, :register)
    get("/repos", RepoController, :index)
    get("/repos/:repo_id", RepoController, :show)
    get("/repos/:repo_id/status", RepoController, :status)
    get("/repos/:repo_id/refs", RepoController, :refs)
    get("/repos/:repo_id/remotes", RepoController, :remotes)
    post("/repos/:repo_id/sync", RepoController, :sync)
    post("/repos/:repo_id/push", PushController, :push)
    post("/repos/:repo_id/files/search", RepoQueryController, :search)
    post("/repos/:repo_id/files/read", RepoQueryController, :read)
    post("/repos/:repo_id/blobs/read", BlobController, :read_repo)
    post("/repos/:repo_id/paths/list", RepoQueryController, :paths)
    post("/repos/:repo_id/query", RepoQueryController, :query)
    post("/repos/:repo_id/graph/refresh", GraphController, :refresh)
    get("/repos/:repo_id/graph/refresh-jobs/:job_id", GraphController, :refresh_job)
    post("/repos/:repo_id/graph/query", GraphController, :query)
    post("/repos/:repo_id/graph/search-files", GraphController, :search_files)
    post("/repos/:repo_id/graph/search-sections", GraphController, :search_sections)
    post("/repos/:repo_id/graph/search-entities", GraphController, :search_entities)
    get("/repos/:repo_id/graph/nodes/:node_id", GraphController, :node)
    post("/repos/:repo_id/graph/related", GraphController, :related)
    post("/repos/:repo_id/graph/subgraph", GraphController, :subgraph)
    post("/repos/:repo_id/context/build", ContextController, :build)
    post("/repos/:repo_id/context/parse-ctx", ContextController, :parse_ctx)
    post("/repos/:repo_id/search/index/refresh", SearchIndexController, :refresh)
    get("/repos/:repo_id/search/index/status", SearchIndexController, :status)
    post("/repos/:repo_id/search/index/compact", SearchIndexController, :compact)
    post("/repos/:repo_id/snapshots/build", SnapshotController, :build)
    get("/repos/:repo_id/snapshots/:snapshot_id", SnapshotController, :show)
    post("/repos/:repo_id/artifacts/export", SnapshotController, :export)
    get("/repos/:repo_id/artifacts", ArtifactController, :index)
    get("/repos/:repo_id/artifacts/:artifact_id", ArtifactController, :show)
    delete("/repos/:repo_id/artifacts/:artifact_id", ArtifactController, :delete)
    post("/repos/:repo_id/workspaces", RepoController, :create_workspace)
    get("/repos/:repo_id/mirrors", RegistryController, :mirrors)
    post("/repos/:repo_id/mirrors", RegistryController, :put_mirror)
    post("/repos/:repo_id/mirrors/:mirror_id/sync", RegistryController, :sync_mirror)
    post("/repos/:repo_id/mirrors/:mirror_id/health", RegistryController, :mirror_health)
    post("/repos/:repo_id/mirrors/:mirror_id/promote", RegistryController, :promote_mirror)
    post("/repos/:repo_id/migrations", MigrationController, :create)
    get("/repos/:repo_id/migrations/:migration_id", MigrationController, :show)

    get("/workspaces/:workspace_id", WorkspaceController, :show)
    post("/workspaces/:workspace_id/close", WorkspaceController, :close)
    get("/workspaces/:workspace_id/tree", FileController, :tree)
    get("/workspaces/:workspace_id/files", FileController, :read)
    put("/workspaces/:workspace_id/files", FileController, :write)
    patch("/workspaces/:workspace_id/files", FileController, :patch)
    delete("/workspaces/:workspace_id/files", FileController, :delete)
    post("/workspaces/:workspace_id/blobs/write", BlobController, :write)
    post("/workspaces/:workspace_id/blobs/delete", BlobController, :delete)
    get("/workspaces/:workspace_id/blobs/download", BlobController, :download)
    put("/workspaces/:workspace_id/blobs/upload", BlobController, :upload)
    post("/workspaces/:workspace_id/blobs/uploads", BlobUploadController, :create)

    put(
      "/workspaces/:workspace_id/blobs/uploads/:upload_id/parts/:part_number",
      BlobUploadController,
      :part
    )

    post(
      "/workspaces/:workspace_id/blobs/uploads/:upload_id/complete",
      BlobUploadController,
      :complete
    )

    delete("/workspaces/:workspace_id/blobs/uploads/:upload_id", BlobUploadController, :abort)
    post("/workspaces/:workspace_id/search", FileController, :search)
    get("/workspaces/:workspace_id/status", FileController, :status)
    get("/workspaces/:workspace_id/diff", FileController, :diff)
    post("/workspaces/:workspace_id/commit", FileController, :commit)
    post("/workspaces/:workspace_id/exec", ExecController, :exec)

    post("/internal/federation/proxy", InternalFederationController, :proxy)

    post(
      "/internal/federation/repos/:repo_id/mirror/export",
      InternalFederationController,
      :mirror_export
    )

    post(
      "/internal/federation/repos/:repo_id/mirror/import",
      InternalFederationController,
      :mirror_import
    )

    get("/internal/federation/health", InternalFederationController, :health)
  end
end
