defmodule TreeDxWeb.AuditController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def events(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, payload} <- TreeDx.Audit.list(params, principal) do
      ok(conn, payload)
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
