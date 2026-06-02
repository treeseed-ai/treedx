defmodule TreeDbWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(TreeDbWeb.AuthPlug)
  end

  scope "/api/v1", TreeDbWeb do
    pipe_through(:api)

    get("/health", HealthController, :health)
    get("/version", HealthController, :version)

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

    get("/node", NodeController, :show)
    get("/registry/nodes", RegistryController, :nodes)
    get("/registry/repos/:repo_id/placement", RegistryController, :placement)
    post("/registry/repos/:repo_id/placement", RegistryController, :put_placement)

    post("/repos/register", RepoController, :register)
    get("/repos", RepoController, :index)
    get("/repos/:repo_id", RepoController, :show)
    get("/repos/:repo_id/status", RepoController, :status)
    get("/repos/:repo_id/refs", RepoController, :refs)
    get("/repos/:repo_id/remotes", RepoController, :remotes)
    post("/repos/:repo_id/sync", RepoController, :sync)
    post("/repos/:repo_id/files/search", RepoQueryController, :search)
    post("/repos/:repo_id/files/read", RepoQueryController, :read)
    post("/repos/:repo_id/paths/list", RepoQueryController, :paths)
    post("/repos/:repo_id/query", RepoQueryController, :query)
    post("/repos/:repo_id/graph/refresh", GraphController, :refresh)
    post("/repos/:repo_id/graph/query", GraphController, :query)
    post("/repos/:repo_id/graph/search-files", GraphController, :search_files)
    post("/repos/:repo_id/graph/search-sections", GraphController, :search_sections)
    post("/repos/:repo_id/graph/search-entities", GraphController, :search_entities)
    get("/repos/:repo_id/graph/nodes/:node_id", GraphController, :node)
    post("/repos/:repo_id/graph/related", GraphController, :related)
    post("/repos/:repo_id/graph/subgraph", GraphController, :subgraph)
    post("/repos/:repo_id/context/build", ContextController, :build)
    post("/repos/:repo_id/context/parse-ctx", ContextController, :parse_ctx)
    post("/repos/:repo_id/workspaces", RepoController, :create_workspace)
    get("/repos/:repo_id/mirrors", RegistryController, :mirrors)
    post("/repos/:repo_id/mirrors", RegistryController, :put_mirror)

    get("/workspaces/:workspace_id", WorkspaceController, :show)
    post("/workspaces/:workspace_id/close", WorkspaceController, :close)
    get("/workspaces/:workspace_id/tree", FileController, :tree)
    get("/workspaces/:workspace_id/files", FileController, :read)
    put("/workspaces/:workspace_id/files", FileController, :write)
    patch("/workspaces/:workspace_id/files", FileController, :patch)
    delete("/workspaces/:workspace_id/files", FileController, :delete)
    post("/workspaces/:workspace_id/search", FileController, :search)
    get("/workspaces/:workspace_id/status", FileController, :status)
    get("/workspaces/:workspace_id/diff", FileController, :diff)
    post("/workspaces/:workspace_id/commit", FileController, :commit)
    post("/workspaces/:workspace_id/exec", ExecController, :exec)
  end
end
