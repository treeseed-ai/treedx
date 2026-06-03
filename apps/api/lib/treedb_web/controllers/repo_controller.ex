defmodule TreeDbWeb.RepoController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def register(conn, params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.register(params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def index(conn, _params) do
    with {:ok, principal} <- require_principal(conn) do
      case TreeDb.Repos.list(principal) do
        {:ok, repos} -> ok(conn, %{repos: repos})
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def show(conn, %{"repo_id" => repo_id}) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.get(repo_id, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def status(conn, %{"repo_id" => repo_id}) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.status(repo_id, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def refs(conn, %{"repo_id" => repo_id}) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.refs(repo_id, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def remotes(conn, %{"repo_id" => repo_id}) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.remotes(repo_id, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def sync(conn, %{"repo_id" => repo_id} = params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Repos.sync(repo_id, params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def create_workspace(conn, %{"repo_id" => repo_id} = params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDb.Workspaces.create(repo_id, params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
