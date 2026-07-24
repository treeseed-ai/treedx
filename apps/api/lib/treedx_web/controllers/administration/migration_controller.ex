defmodule TreeDxWeb.MigrationController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def create(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Migrations.create(repo_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def show(conn, %{"repo_id" => repo_id, "migration_id" => migration_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Migrations.get(repo_id, migration_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end
end
