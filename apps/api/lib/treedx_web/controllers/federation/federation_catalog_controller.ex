defmodule TreeDxWeb.FederationCatalogController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def catalog(conn, _params) do
    case TreeDx.Federation.NodeAuth.verify_conn(conn, "catalog_sync") do
      {:ok, _payload} ->
        ok(conn, %{catalog: TreeDx.Federation.Catalog.local()})

      {:error, _node_error} ->
        with {:ok, principal} <- require_principal(conn),
             {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:read") do
          ok(conn, %{catalog: TreeDx.Federation.Catalog.local()})
        else
          {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
        end
    end
  end

  def push(conn, %{"catalog" => catalog}) do
    case TreeDx.Federation.NodeAuth.verify_conn(conn, "catalog_sync") do
      {:ok, payload} ->
        with :ok <- TreeDx.Federation.Catalog.import(catalog, payload["sub"]) do
          ok(conn, %{status: "accepted"})
        else
          {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
        end

      {:error, _node_error} ->
        with {:ok, principal} <- require_principal(conn),
             {:ok, _scope} <-
               TreeDx.Capabilities.require_capability(principal, "federation:sync"),
             :ok <- TreeDx.Federation.Catalog.import(catalog) do
          ok(conn, %{status: "accepted"})
        else
          {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
        end
    end
  end

  def sync(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:sync"),
         :ok <- TreeDx.Federation.CatalogSync.sync_now() do
      ok(conn, %{status: "synced"})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def routes(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:read"),
         {:ok, routes} <- TreeDx.Federation.Catalog.routes() do
      ok(conn, %{routes: routes})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
