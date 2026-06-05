defmodule TreeDbWeb.ArtifactController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers
  import TreeDbWeb.FederationProxyHelpers

  def index(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_read(
      conn,
      repo_id,
      params,
      [pool: :snapshot, allow_mirrors?: false],
      fn conn ->
        with {:ok, principal} <- require_principal(conn) do
          handle_result(conn, TreeDb.Artifacts.list(repo_id, params, principal))
        else
          {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
        end
      end
    )
  end

  def show(conn, %{"repo_id" => repo_id, "artifact_id" => artifact_id}) do
    maybe_proxy_repo_read(conn, repo_id, nil, [pool: :snapshot, allow_mirrors?: false], fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDb.Artifacts.get(repo_id, artifact_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def delete(conn, %{"repo_id" => repo_id, "artifact_id" => artifact_id}) do
    maybe_proxy_repo_write(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDb.Artifacts.delete(repo_id, artifact_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def cleanup(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:write") do
      handle_result(conn, TreeDb.Artifacts.cleanup(params, principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
