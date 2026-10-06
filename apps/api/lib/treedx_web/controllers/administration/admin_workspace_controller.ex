defmodule TreeDxWeb.AdminWorkspaceController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def quarantined(conn, _params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDx.Workspaces.quarantined(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
