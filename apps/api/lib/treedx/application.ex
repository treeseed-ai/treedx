defmodule TreeDx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    data_dir =
      Application.get_env(:treedx, :data_dir) || System.get_env("TREEDX_DATA_DIR") ||
        "/var/lib/treedx"

    Application.put_env(:treedx, :data_dir, data_dir)

    TreeDx.ConfigValidation.validate_boot!()
    :ok = validate_auth!()
    TreeDx.Store.init!(node_id: node_id())
    TreeDx.Federation.NodeIdentity.ensure_keys!()

    if TreeDx.Auth.mode() == "dev" do
      {:ok, _} = TreeDx.Store.seed_dev_records(node_id(), base_url())
    else
      {:ok, _} = TreeDx.Store.seed_local_records(node_id(), base_url())
    end

    TreeDx.Audit.append("app.data_dir_initialized", %{
      node_id: node_id(),
      data: %{dataDir: data_dir}
    })

    children = [
      TreeDx.Observability.Metrics,
      TreeDx.Observability.Telemetry,
      {Task.Supervisor, name: TreeDx.Runtime.Pool.TaskSupervisor},
      TreeDx.Runtime.Pool,
      TreeDx.RepositoryCache,
      TreeDx.Graph.IndexCache,
      TreeDx.Cache.Manager,
      TreeDx.Graph.RefreshCoordinator,
      TreeDx.Artifacts.Index,
      TreeDx.Audit.Writer,
      TreeDx.Federation.CatalogSync,
      TreeDx.Auth.JwksCache,
      TreeDxWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TreeDx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TreeDxWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp node_id, do: System.get_env("TREEDX_NODE_ID") || "node_local"

  defp validate_auth! do
    case TreeDx.Auth.validate_boot_config() do
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
