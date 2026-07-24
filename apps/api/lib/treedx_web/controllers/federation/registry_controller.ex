defmodule TreeDxWeb.RegistryController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def nodes(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "registry:read", nil),
         {:ok, nodes} <- TreeDx.Registry.nodes() do
      ok(conn, %{nodes: nodes})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def placement(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, _scope} <-
             TreeDx.Capabilities.require_capability(principal, "registry:read", repo_id),
           {:ok, placement} <- TreeDx.Registry.placement(repo_id) do
        ok(conn, %{placement: placement})
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def put_placement(conn, params = %{"repo_id" => repo_id}) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, _scope} <-
             TreeDx.Capabilities.require_capability(principal, "registry:write", repo_id) do
        input = %{
          repositoryId: repo_id,
          primaryNodeId: params["primaryNodeId"] || "node_local",
          mirrorNodeIds: params["mirrorNodeIds"] || [],
          readPolicy: params["readPolicy"] || "primary_or_mirror",
          writePolicy: params["writePolicy"] || "primary_only",
          migrationState: params["migrationState"] || "stable"
        }

        TreeDx.Audit.append("registry.placement.updated", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          repo_id: repo_id,
          operation: "registry.placement.put",
          status: "ok",
          request_id: conn.assigns[:request_id]
        })

        handle_result(conn, TreeDx.Registry.put_placement(input) |> wrap(:placement))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def mirrors(conn, %{"repo_id" => repo_id}) do
    maybe_proxy_repo_read(conn, repo_id, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, result} <- TreeDx.Mirrors.list(repo_id, principal) do
        ok(conn, result)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def put_mirror(conn, params = %{"repo_id" => repo_id}) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, result} <- TreeDx.Mirrors.create(repo_id, params, principal) do
        ok(conn, result)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def sync_mirror(conn, params = %{"repo_id" => repo_id, "mirror_id" => mirror_id}) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, result} <- TreeDx.Mirrors.sync(repo_id, mirror_id, params, principal) do
        ok(conn, result)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def mirror_health(conn, params = %{"repo_id" => repo_id, "mirror_id" => mirror_id}) do
    maybe_proxy_repo_read(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, result} <- TreeDx.Mirrors.health(repo_id, mirror_id, params, principal) do
        ok(conn, result)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def promote_mirror(conn, params = %{"repo_id" => repo_id, "mirror_id" => mirror_id}) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, result} <- TreeDx.Mirrors.promote(repo_id, mirror_id, params, principal) do
        ok(conn, result)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  defp wrap({:ok, value}, key), do: {:ok, %{key => value}}
  defp wrap(error, _key), do: error
end
