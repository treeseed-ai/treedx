defmodule TreeDb.Graph.ContextPack do
  @moduledoc false

  alias TreeDb.Graph.Native

  def build(repo_id, params, principal) do
    with {:ok, ctx} <- TreeDb.Graph.Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- TreeDb.Graph.load_authorized_index(ctx, params),
         {:ok, pack} <-
           Native.build_context_pack(index, %{
             graphQuery: TreeDb.Graph.query_request(params),
             budget: params["budget"] || %{}
           }) do
      TreeDb.Audit.append("context.built", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        data: %{
          graphVersion: index["manifest"]["graphVersion"],
          resultCount: length(pack["nodes"] || [])
        }
      })

      diagnostics =
        Map.merge(pack["diagnostics"] || %{}, %{
          "effectiveScope" => %{
            "repoId" => repo_id,
            "ref" => ctx.ref,
            "paths" => ctx.scope["paths"] || []
          }
        })

      {:ok,
       TreeDb.Graph.base(ctx, index)
       |> Map.merge(Map.delete(pack, "diagnostics"))
       |> Map.put(:diagnostics, diagnostics)}
    end
  end
end
