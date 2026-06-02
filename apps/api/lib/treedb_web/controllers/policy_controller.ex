defmodule TreeDbWeb.PolicyController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def effective_scope(conn, params) do
    principal = conn.assigns[:principal]
    repo_id = params["repoId"] || params["repo_id"]

    case TreeDb.Capabilities.effective_scope(principal, repo_id, allow_dev_default: true) do
      {:ok, scope} ->
        TreeDb.Audit.append("policy.effective_scope_resolved", %{
          actor_id: scope["actorId"],
          tenant_id: scope["tenantId"],
          repo_id: repo_id,
          operation: "policy.effective_scope",
          status: "ok",
          request_id: conn.assigns[:request_id],
          effective_scope: scope
        })

        ok(conn, %{effectiveScope: scope})

      {:error, error} ->
        error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def refresh(conn, _params) do
    if TreeDb.Auth.mode() == "dev" do
      TreeDb.Audit.append("policy.refreshed", %{status: "ok", data: %{mode: "dev"}})
      ok(conn, %{refreshed: false, mode: "dev"})
    else
      with {:ok, principal} <- require_principal(conn),
           {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:write"),
           {:ok, record} <-
             TreeDb.Store.put_policy_refresh(%{
               id: TreeDb.Ids.short("pol"),
               source: "connected",
               actorId: principal["actorId"],
               tenantId: principal["tenantId"],
               status: "noop",
               data: %{},
               refreshedAt: DateTime.utc_now() |> DateTime.to_iso8601()
             }) do
        TreeDb.Audit.append("policy.refreshed", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          operation: "policy.refresh",
          status: "ok",
          request_id: conn.assigns[:request_id]
        })

        ok(conn, %{refreshed: false, mode: "connected", refresh: record})
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end
  end
end
