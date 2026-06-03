defmodule TreeDbWeb.GlobalQueryController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def search(conn, params), do: execute(conn, :search, params)
  def query(conn, params), do: execute(conn, :query, params)
  def context(conn, params), do: execute(conn, :context, params)
  def graph(conn, params), do: execute(conn, :graph, params)

  defp execute(conn, operation, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "query:federated"),
         auth_header <- conn |> get_req_header("authorization") |> List.first(),
         {:ok, payload} <-
           TreeDb.Federation.Executor.execute(operation, params, principal, auth_header) do
      ok(conn, payload)
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
