defmodule TreeDxWeb.RepoQueryController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def read(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, [pool: :repository_query], fn conn ->
        cached(conn, repo_id, params, "files:read", :read, &TreeDx.RepositoryQuery.read/3)
      end)

  def paths(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, [pool: :repository_query], fn conn ->
        cached(conn, repo_id, params, "files:read", :paths, &TreeDx.RepositoryQuery.paths/3)
      end)

  def search(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, [pool: :repository_query], fn conn ->
        cached(conn, repo_id, params, "files:search", :search, &TreeDx.RepositoryQuery.search/3)
      end)

  def query(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, [pool: :repository_query], fn conn ->
        capability = query_capability(params["type"])
        cached(conn, repo_id, params, capability, :query, &TreeDx.RepositoryQuery.query/3)
      end)

  defp query_capability(type) when type in [nil, "text", "combined"], do: "files:search"
  defp query_capability("changed_path"), do: "git:diff"
  defp query_capability(_type), do: "files:read"

  defp cached(conn, repo_id, params, capability, operation, execute) do
    with_principal(conn, fn principal ->
      with {:ok, ctx} <- TreeDx.RepositoryQuery.context(repo_id, params, principal, capability) do
        result =
          TreeDx.RepositoryCache.result(ctx, operation, params, fn ->
            execute.(repo_id, Map.put(params, "__ctx", ctx), principal)
          end)

        audit_served(result, ctx, operation)
        result
      end
    end)
  end

  defp audit_served({:ok, _response}, ctx, operation) do
    TreeDx.Audit.append("repo.response_served", %{
      actor_id: ctx.principal["actorId"],
      tenant_id: ctx.principal["tenantId"],
      repo_id: ctx.repo["id"],
      data: %{operation: operation, resolvedRef: ctx.resolved_ref}
    })
  end

  defp audit_served(_result, _ctx, _operation), do: :ok

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
