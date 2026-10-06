defmodule TreeDxWeb.SearchIndexController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def refresh(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
        with_principal(conn, &TreeDx.Search.Index.refresh(repo_id, params, &1))
      end)

  def status(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, fn conn ->
        with_principal(conn, &TreeDx.Search.Index.status(repo_id, params, &1))
      end)

  def compact(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
        with_principal(conn, &TreeDx.Search.Index.compact(repo_id, params, &1))
      end)

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
