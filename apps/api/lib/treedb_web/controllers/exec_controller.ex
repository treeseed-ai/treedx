defmodule TreeDbWeb.ExecController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def exec(conn, %{"workspace_id" => workspace_id} = params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Exec.run(workspace_id, params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
