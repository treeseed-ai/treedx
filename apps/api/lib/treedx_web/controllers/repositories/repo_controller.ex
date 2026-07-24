defmodule TreeDxWeb.RepoController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def register(conn, params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDx.Repos.register(params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def create(conn, params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDx.Repos.create(params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def import_local(conn, params) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, TreeDx.Repos.import_local(params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def index(conn, _params) do
    with {:ok, principal} <- require_principal(conn) do
      case TreeDx.Repos.list(principal) do
        {:ok, repos} -> ok(conn, %{repos: repos})
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def show(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Repos.get(repo_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def status(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Repos.status(repo_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def refs(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Repos.refs(repo_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def remotes(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Repos.remotes(repo_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def sync(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Repos.sync(repo_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def create_workspace(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Workspaces.create(repo_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end
end
