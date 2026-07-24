defmodule TreeDxWeb.PolicyController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def effective_scope(conn, params) do
    principal = conn.assigns[:principal]
    repo_id = params["repoId"] || params["repo_id"]

    case TreeDx.Capabilities.effective_scope(principal, repo_id, allow_dev_default: true) do
      {:ok, scope} ->
        TreeDx.Audit.append("policy.effective_scope_resolved", %{
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

  def refresh(conn, params) do
    revocations = params["revocations"] || []

    if TreeDx.Auth.mode() == "dev" and revocations == [] do
      TreeDx.Audit.append("policy.refreshed", %{status: "ok", data: %{mode: "dev"}})
      ok(conn, %{refreshed: false, mode: "dev"})
    else
      with {:ok, principal} <- require_principal(conn),
           {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write"),
           {:ok, applied} <- apply_revocations(revocations, principal, conn.assigns[:request_id]),
           {:ok, record} <-
             TreeDx.Store.put_policy_refresh(%{
               id: TreeDx.Ids.short("pol"),
               source: params["source"] || "connected",
               actorId: principal["actorId"],
               tenantId: principal["tenantId"],
               status: if(applied == [], do: "noop", else: "applied"),
               data: %{revocations: applied},
               refreshedAt: DateTime.utc_now() |> DateTime.to_iso8601()
             }) do
        TreeDx.Audit.append("policy.refreshed", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          operation: "policy.refresh",
          status: "ok",
          request_id: conn.assigns[:request_id]
        })

        ok(conn, %{refreshed: applied != [], mode: TreeDx.Auth.mode(), refresh: record})
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end
  end

  defp apply_revocations([], _principal, _request_id), do: {:ok, []}

  defp apply_revocations(revocations, principal, request_id) when is_list(revocations) do
    applied =
      Enum.map(revocations, fn revocation ->
        grant_id = revocation["id"] || revocation["grantId"]
        {:ok, grants} = TreeDx.Capabilities.list_grants(%{})

        case Enum.find(grants, &(&1["id"] == grant_id)) do
          nil ->
            nil

          grant ->
            revoked =
              grant
              |> Map.put("revokedAt", DateTime.utc_now() |> DateTime.to_iso8601())
              |> Map.put("revokedByActorId", principal["actorId"])
              |> Map.put("revocationReason", revocation["reason"] || "policy_refresh")

            {:ok, _} = TreeDx.Capabilities.put_grant(revoked)

            TreeDx.Audit.append("policy.revocation_applied", %{
              actor_id: principal["actorId"],
              tenant_id: principal["tenantId"],
              operation: "policy.refresh",
              status: "ok",
              request_id: request_id,
              data: %{grantId: grant_id}
            })

            %{grantId: grant_id}
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, applied}
  end

  defp apply_revocations(_revocations, _principal, _request_id),
    do: {:error, %{code: "validation_error", message: "revocations must be an array."}}
end
