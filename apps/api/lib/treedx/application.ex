defmodule TreeDx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    data_dir =
      System.get_env("TREEDX_DATA_DIR") || Application.get_env(:treedx, :data_dir) ||
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
      :ok = bootstrap_configured_trust_grant()
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

  defp bootstrap_configured_trust_grant do
    actor_id = System.get_env("TREEDX_BOOTSTRAP_TRUST_ACTOR_ID")
    tenant_id = System.get_env("TREEDX_BOOTSTRAP_TRUST_TENANT_ID")

    cond do
      blank?(actor_id) and blank?(tenant_id) ->
        :ok

      blank?(actor_id) or blank?(tenant_id) ->
        raise "TREEDX_BOOTSTRAP_TRUST_ACTOR_ID and TREEDX_BOOTSTRAP_TRUST_TENANT_ID must be configured together."

      true ->
        capabilities =
          System.get_env("TREEDX_BOOTSTRAP_TRUST_CAPABILITIES")
          |> csv(TreeDx.Capabilities.canonical())

        refs = System.get_env("TREEDX_BOOTSTRAP_TRUST_REFS") |> csv(["*"])
        paths = System.get_env("TREEDX_BOOTSTRAP_TRUST_PATHS") |> csv(["**"])
        repo_ids = System.get_env("TREEDX_BOOTSTRAP_TRUST_REPO_IDS") |> csv(["*"])

        {:ok, _grant} =
          TreeDx.Capabilities.put_grant(%{
            "actorId" => actor_id,
            "tenantId" => tenant_id,
            "repoIds" => repo_ids,
            "capabilities" => capabilities,
            "refs" => refs,
            "paths" => paths
          })

        :ok
    end
  end

  defp csv(nil, fallback), do: fallback

  defp csv(value, fallback) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> fallback
      entries -> entries
    end
  end

  defp blank?(value), do: !is_binary(value) or String.trim(value) == ""

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
