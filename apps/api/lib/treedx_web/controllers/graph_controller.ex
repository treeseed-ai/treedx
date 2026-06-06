defmodule TreeDxWeb.GraphController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def refresh(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
        with_principal(conn, &TreeDx.Graph.refresh(repo_id, params, &1))
      end)

  def refresh_job(conn, %{"repo_id" => repo_id, "job_id" => job_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.refresh_job(repo_id, job_id, params, &1))
        end
      )

  def query(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.query(repo_id, params, &1))
        end
      )

  def search_files(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.search_files(repo_id, params, &1))
        end
      )

  def search_sections(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.search_sections(repo_id, params, &1))
        end
      )

  def search_entities(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.search_entities(repo_id, params, &1))
        end
      )

  def node(conn, %{"repo_id" => repo_id, "node_id" => node_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.node(repo_id, node_id, params, &1))
        end
      )

  def related(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.related(repo_id, params, &1))
        end
      )

  def subgraph(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(
        conn,
        repo_id,
        params,
        [pool: :graph, allow_mirrors?: false],
        fn conn ->
          with_principal(conn, &TreeDx.Graph.subgraph(repo_id, params, &1))
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
