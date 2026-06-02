defmodule TreeDbWeb.MigrationController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def create(conn, %{"repo_id" => repo_id} = params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Migrations.create(repo_id, params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def show(conn, %{"repo_id" => repo_id, "migration_id" => migration_id}) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Migrations.get(repo_id, migration_id, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
