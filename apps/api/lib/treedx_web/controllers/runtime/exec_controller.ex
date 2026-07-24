defmodule TreeDxWeb.ExecController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def exec(conn, %{"workspace_id" => workspace_id} = params) do
    maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Exec.run(workspace_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end
end
