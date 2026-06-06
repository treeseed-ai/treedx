defmodule TreeDxWeb.CapabilityController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def capabilities(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      ok(conn, %{capabilities: TreeDx.Capabilities.canonical()})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def grants(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <-
           TreeDx.Capabilities.require_capability(principal, "policy:read", params["repoId"]),
         {:ok, grants} <- TreeDx.Capabilities.list_grants(params) do
      ok(conn, %{grants: grants})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def put_grant(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <-
           TreeDx.Capabilities.require_capability(principal, "policy:write", first_repo(params)),
         {:ok, grant} <- TreeDx.Capabilities.put_grant(params) do
      TreeDx.Audit.append("policy.grant.updated", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        status: "ok",
        operation: "policy.grant.put",
        request_id: conn.assigns[:request_id],
        data: %{targetActorId: params["actorId"], repoIds: params["repoIds"] || []}
      })

      ok(conn, %{grant: grant})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp first_repo(%{"repoIds" => [repo_id | _]}), do: repo_id
  defp first_repo(_), do: nil
end
