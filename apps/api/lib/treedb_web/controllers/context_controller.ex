defmodule TreeDbWeb.ContextController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers
  import TreeDbWeb.FederationProxyHelpers

  def build(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDb.Graph.build_context(repo_id, params, &1))
        end
      )

  def parse_ctx(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDb.Graph.parse_ctx(repo_id, params, &1))
        end
      )

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
