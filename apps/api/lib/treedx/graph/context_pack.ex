defmodule TreeDx.Graph.ContextPack do
  @moduledoc false

  alias TreeDx.Graph.{Builder, Native}

  def build(repo_id, params, principal) do
    with {:ok, ctx} <- TreeDx.Graph.Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index, graph_source} <- load_or_build_authorized_index(ctx, params),
         {:ok, pack} <-
           Native.build_context_pack(index, %{
             graphQuery: TreeDx.Graph.query_request(params),
             budget: budget(params)
           }) do
      TreeDx.Audit.append("context.built", %{
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
          "mode" => context_mode(params),
          "graphSource" => graph_source,
          "budget" => budget_diagnostics(params, pack),
          "provenancePaths" => pack["includedPaths"] || [],
          "effectiveScope" => %{
            "repoId" => repo_id,
            "ref" => ctx.ref,
            "paths" => ctx.scope["paths"] || []
          }
        })

      {:ok,
       TreeDx.Graph.base(ctx, index)
       |> Map.merge(Map.delete(pack, "diagnostics"))
       |> Map.put(:mode, context_mode(params))
       |> Map.put(:diagnostics, diagnostics)}
    end
  end

  # Exact immutable commits are valid query authorities even when no persisted graph
  # generation has been published for that spelling of the ref. Build a bounded,
  # authorization-filtered transient index instead of rejecting the context request.
  # The transient index is deliberately not published as the repository's shared graph:
  # a caller's path scope may be narrower than another caller's scope.
  defp load_or_build_authorized_index(ctx, params) do
    case TreeDx.Graph.load_authorized_index(ctx, params) do
      {:ok, index} ->
        {:ok, index, "indexed"}

      {:error, %{code: "graph_not_ready"}} ->
        build_transient_authorized_index(ctx, params)

      {:error, %{"code" => "graph_not_ready"}} ->
        build_transient_authorized_index(ctx, params)

      other ->
        other
    end
  end

  defp build_transient_authorized_index(ctx, params) do
    with {:ok, input} <- Builder.build_input(ctx, params, nil),
         {:ok, index} <- Native.build_graph_index(input) do
      {:ok, index, "on-demand"}
    end
  end

  defp budget(params) do
    requested = params["budget"] || %{}
    mode = context_mode(params)

    requested
    |> Map.put_new("maxNodes", default_max_nodes(mode))
    |> Map.put_new("maxTokens", default_max_tokens())
    |> Map.put("includeMode", include_mode(mode, requested["includeMode"]))
  end

  defp budget_diagnostics(params, pack) do
    requested = budget(params)
    used_nodes = length(pack["nodes"] || [])
    estimate = pack["totalTokenEstimate"] || 0

    %{
      "requestedMaxNodes" => requested["maxNodes"],
      "usedNodes" => used_nodes,
      "requestedMaxTokens" => requested["maxTokens"],
      "estimatedTokens" => estimate,
      "truncated" => used_nodes >= requested["maxNodes"] or estimate >= requested["maxTokens"]
    }
  end

  defp context_mode(params) do
    case params["mode"] || System.get_env("TREEDX_CONTEXT_DEFAULT_MODE") || "brief" do
      mode when mode in ["brief", "detailed", "citations", "mixed"] -> mode
      _ -> "brief"
    end
  end

  defp include_mode("brief", existing), do: existing || "sections"
  defp include_mode("detailed", _existing), do: "files"
  defp include_mode("citations", _existing), do: "sections"
  defp include_mode("mixed", _existing), do: "mixed"

  defp default_max_nodes("brief"), do: 8
  defp default_max_nodes("detailed"), do: 20
  defp default_max_nodes("citations"), do: 12
  defp default_max_nodes("mixed"), do: 16

  defp default_max_tokens do
    System.get_env("TREEDX_CONTEXT_MAX_TOKENS_DEFAULT", "4000")
    |> String.to_integer()
  rescue
    _ -> 4000
  end
end
