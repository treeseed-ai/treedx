defmodule TreeDxWeb.FederationController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def plan_query(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "query:federated"),
         {:ok, payload} <- TreeDx.Federation.plan_query(params, principal) do
      ok(conn, payload)
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
