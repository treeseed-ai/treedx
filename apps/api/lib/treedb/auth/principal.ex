defmodule TreeDb.Auth.Principal do
  @moduledoc false

  def from_dev(actor_id, tenant_id) do
    %{actorId: actor_id, tenantId: tenant_id, authMode: "dev"}
  end

  def from_claims(claims) do
    actor_id = claims["treedb_actor_id"] || claims["sub"]
    tenant_id = claims["treedb_tenant_id"]

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
             repoIds: claims["treedb_repo_ids"] || [],
             capabilities: claims["treedb_capabilities"] || [],
             refs: claims["treedb_refs"] || [],
             paths: claims["treedb_paths"] || []
           }
         }}
    end
  end
end
