defmodule TreeDx.Auth.Principal do
  @moduledoc false

  def from_dev(actor_id, tenant_id) do
    %{actorId: actor_id, tenantId: tenant_id, authMode: "dev"}
  end

  def from_claims(claims) do
    actor_id = claims["treedx_actor_id"] || claims["sub"]
    tenant_id = claims["treedx_tenant_id"]

    cond do
      !is_binary(actor_id) or actor_id == "" ->
        {:error, %{code: "invalid_token", message: "Token actor claim is required."}}

      !is_binary(tenant_id) or tenant_id == "" ->
        {:error, %{code: "invalid_token", message: "Token tenant claim is required."}}

      true ->
        {:ok,
         %{
           actorId: actor_id,
           tenantId: tenant_id,
           authMode: "connected",
           tokenId: claims["jti"],
           tokenScope: %{
             repoIds: claims["treedx_repo_ids"] || [],
             capabilities: claims["treedx_capabilities"] || [],
             refs: claims["treedx_refs"] || [],
             paths: claims["treedx_paths"] || []
           }
         }}
    end
  end
end
