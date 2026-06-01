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
    post("/auth/dev-token", AuthController, :dev_token)
    get("/policy/effective-scope", PolicyController, :effective_scope)
    post("/policy/refresh", PolicyController, :refresh)

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
    post("/repos/:repo_id/workspaces", RepoController, :create_workspace)
    get("/repos/:repo_id/mirrors", RegistryController, :mirrors)
    post("/repos/:repo_id/mirrors", RegistryController, :put_mirror)

    get("/workspaces/:workspace_id", WorkspaceController, :show)
    post("/workspaces/:workspace_id/close", WorkspaceController, :close)
  end
end
