defmodule TreeDb.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    data_dir =
      Application.get_env(:treedb, :data_dir) || System.get_env("TREEDB_DATA_DIR") ||
        "/var/lib/treedb"

    Application.put_env(:treedb, :data_dir, data_dir)

    TreeDb.ConfigValidation.validate_boot!()
    :ok = validate_auth!()
    TreeDb.Store.init!(node_id: node_id())
    TreeDb.Federation.NodeIdentity.ensure_keys!()

    if TreeDb.Auth.mode() == "dev" do
      {:ok, _} = TreeDb.Store.seed_dev_records(node_id(), base_url())
    else
      {:ok, _} = TreeDb.Store.seed_local_records(node_id(), base_url())
    end

    TreeDb.Audit.append("app.data_dir_initialized", %{
      node_id: node_id(),
      data: %{dataDir: data_dir}
    })

    children = [
      TreeDb.Observability.Metrics,
      TreeDb.Observability.Telemetry,
      {Task.Supervisor, name: TreeDb.Runtime.Pool.TaskSupervisor},
      TreeDb.Runtime.Pool,
      TreeDb.RepositoryCache,
      TreeDb.Graph.IndexCache,
      TreeDb.Cache.Manager,
      TreeDb.Graph.RefreshCoordinator,
      TreeDb.Artifacts.Index,
      TreeDb.Audit.Writer,
      TreeDb.Federation.CatalogSync,
      TreeDb.Auth.JwksCache,
      TreeDbWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TreeDb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TreeDbWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp node_id, do: System.get_env("TREEDB_NODE_ID") || "node_local"

  defp validate_auth! do
    case TreeDb.Auth.validate_boot_config() do
      :ok -> :ok
      {:error, error} -> raise error[:message] || error["message"] || "Invalid auth config."
    end
  end

  defp base_url do
    host = System.get_env("PHX_HOST") || "localhost"
    port = System.get_env("PORT") || "4000"
    "http://#{host}:#{port}"
  end
end
