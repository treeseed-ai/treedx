defmodule TreeDbWeb.GraphController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def refresh(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.refresh(repo_id, params, &1))

  def query(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.query(repo_id, params, &1))

  def search_files(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.search_files(repo_id, params, &1))

  def search_sections(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.search_sections(repo_id, params, &1))

  def search_entities(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.search_entities(repo_id, params, &1))

  def node(conn, %{"repo_id" => repo_id, "node_id" => node_id} = params),
    do: with_principal(conn, &TreeDb.Graph.node(repo_id, node_id, params, &1))

  def related(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.related(repo_id, params, &1))

  def subgraph(conn, %{"repo_id" => repo_id} = params),
    do: with_principal(conn, &TreeDb.Graph.subgraph(repo_id, params, &1))

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
