defmodule TreeDxWeb.FileController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def tree(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.tree(workspace_id, params, &1))
      end)

  def read(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.read(workspace_id, params, &1))
      end)

  def write(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.write(workspace_id, params, &1))
      end)

  def patch(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.patch(workspace_id, params, &1))
      end)

  def delete(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.delete(workspace_id, params, &1))
      end)

  def search(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.search(workspace_id, params, &1))
      end)

  def status(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.status(workspace_id, params, &1))
      end)

  def diff(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.diff(workspace_id, params, &1))
      end)

  def commit(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Files.commit(workspace_id, params, &1))
      end)

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
