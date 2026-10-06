defmodule TreeDx.Federation.CatalogSync do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def sync_now, do: GenServer.call(__MODULE__, :sync_now, 30_000)

  def init(state) do
    if enabled?() do
      TreeDx.Federation.Trust.bootstrap_parents!()
      schedule()
    end

    {:ok, state}
  end

  def handle_call(:sync_now, _from, state) do
    {:reply, sync(), state}
  end

  def handle_info(:sync, state) do
    sync()
    schedule()
    {:noreply, state}
  end

  defp sync do
    with {:ok, peers} <- TreeDx.Store.list_federation_peers() do
      peers
      |> Enum.filter(&("trusted_for_catalog" in (&1["trustStates"] || [])))
      |> Enum.each(&pull_catalog/1)

      :ok
    end
  end

  defp pull_catalog(%{"id" => node_id, "baseUrl" => base_url})
       when is_binary(base_url) and base_url != "" do
    case TreeDx.Federation.HttpClient.get_json(
           node_id,
           base_url,
           "/api/v1/federation/catalog",
           "catalog_sync"
         ) do
      {:ok, status, _headers, body} when status in 200..299 ->
        with {:ok, %{"ok" => true, "catalog" => catalog}} <- Jason.decode(body) do
          TreeDx.Federation.Catalog.import(catalog, node_id)
        end

      _ ->
        :ok
    end
  end

  defp pull_catalog(_), do: :ok

  defp schedule, do: Process.send_after(self(), :sync, interval())
  defp enabled?, do: System.get_env("TREEDX_FEDERATION_ENABLED", "true") not in ["false", "0"]

  defp interval do
    System.get_env("TREEDX_FEDERATION_CATALOG_SYNC_INTERVAL_MS", "5000")
    |> String.to_integer()
  end
end
