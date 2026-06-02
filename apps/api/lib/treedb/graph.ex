defmodule TreeDb.Graph do
  @moduledoc false

  alias TreeDb.Graph.{Auth, Builder, ContextPack, Dsl, Filter, Native}

  def refresh(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:refresh"),
         {:ok, _} <- TreeDb.Capabilities.require_capability(principal, "files:read", repo_id),
         {:ok, _} <- TreeDb.Capabilities.require_capability(principal, "git:read", repo_id),
         {:ok, previous} <- Native.read_latest_graph_manifest(repo_id, ctx.ref),
         {:ok, input} <- Builder.build_input(ctx, params, previous),
         {:ok, index} <- Native.build_graph_index(input),
         {:ok, manifest} <- Native.write_graph_segments(index) do
      audit("graph.refreshed", ctx, %{graphVersion: manifest["graphVersion"]})

      {:ok,
       %{
         ready: true,
         repoId: repo_id,
         ref: ctx.ref,
         resolvedRef: ctx.resolved_ref,
         graphVersion: manifest["graphVersion"],
         snapshotRoot: snapshot_root(repo_id, manifest["graphVersion"]),
         changed: manifest["delta"],
         metrics: manifest["metrics"],
         diagnostics: index["diagnostics"]
       }}
    end
  end

  def search_files(repo_id, params, principal),
    do: search(repo_id, params, principal, "files", "graph.files_searched")

  def search_sections(repo_id, params, principal),
    do: search(repo_id, params, principal, "sections", "graph.sections_searched")

  def search_entities(repo_id, params, principal),
    do: search(repo_id, params, principal, "entities", "graph.entities_searched")

  def node(repo_id, node_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- load_authorized_index(ctx, params),
         node when is_map(node) <- Enum.find(index["nodes"], &(&1["id"] == node_id)) do
      audit("graph.node_read", ctx, %{graphVersion: index["manifest"]["graphVersion"]})
      {:ok, %{repoId: repo_id, graphVersion: index["manifest"]["graphVersion"], node: node}}
    else
      nil -> {:error, %{code: "not_found", message: "Graph node not found."}}
      other -> other
    end
  end

  def query(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- load_authorized_index(ctx, params),
         {:ok, result} <- Native.query_graph(index, query_request(params)) do
      audit("graph.queried", ctx, %{
        graphVersion: index["manifest"]["graphVersion"],
        resultCount: length(result["nodes"] || [])
      })

      {:ok, Map.merge(base(ctx, index), result)}
    end
  end

  def related(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- load_authorized_index(ctx, params),
         node_id when is_binary(node_id) <- params["nodeId"],
         {:ok, result} <- Native.related_nodes(index, node_id, query_request(params)) do
      audit("graph.related_read", ctx, %{
        graphVersion: index["manifest"]["graphVersion"],
        resultCount: length(result["nodes"] || [])
      })

      {:ok, Map.merge(base(ctx, index), result)}
    else
      nil -> {:error, %{code: "validation_error", message: "nodeId is required."}}
      other -> other
    end
  end

  def subgraph(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- load_authorized_index(ctx, params),
         seed_ids when is_list(seed_ids) <- params["seedIds"],
         {:ok, result} <- Native.subgraph(index, seed_ids, query_request(params)) do
      audit("graph.subgraph_read", ctx, %{
        graphVersion: index["manifest"]["graphVersion"],
        resultCount: length(result["nodes"] || [])
      })

      {:ok, Map.merge(base(ctx, index), Map.put(result, "seedId", Enum.join(seed_ids, ",")))}
    else
      nil -> {:error, %{code: "validation_error", message: "seedIds is required."}}
      other -> other
    end
  end

  def build_context(repo_id, params, principal), do: ContextPack.build(repo_id, params, principal)

  def parse_ctx(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, parsed} <- Dsl.parse(params["source"] || "") do
      audit("context.dsl_parsed", ctx, %{resultCount: length(parsed[:errors] || [])})
      {:ok, parsed}
    end
  end

  def load_authorized_index(ctx, params) do
    with {:ok, manifest} <- Native.read_latest_graph_manifest(ctx.repo["id"], ctx.ref),
         {:ok, manifest} <- require_manifest(manifest),
         {:ok, index} <- Native.read_graph_segments(ctx.repo["id"], manifest["graphVersion"]) do
      {:ok, Filter.authorize(index, ctx.scope, params)}
    end
  end

  def query_request(params) do
    %{
      seedIds: params["seedIds"] || [],
      seeds: params["seeds"] || [],
      query: params["query"],
      scope: params["scope"],
      scopePaths: params["scopePaths"] || [],
      where: params["where"] || [],
      relations: params["relations"] || [],
      view: params["view"],
      options: normalize_options(params)
    }
  end

  defp search(repo_id, params, principal, scope, event) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:query"),
         {:ok, index} <- load_authorized_index(ctx, params),
         {:ok, results} <-
           Native.search_graph(index, %{
             query: params["query"] || "",
             scope: scope,
             options: normalize_options(params)
           }) do
      audit(event, ctx, %{
        graphVersion: index["manifest"]["graphVersion"],
        resultCount: length(results)
      })

      {:ok, Map.merge(base(ctx, index), %{results: results})}
    end
  end

  defp normalize_options(params) do
    options = params["options"] || %{}

    %{
      limit: params["limit"] || options["limit"],
      nodeTypes: options["nodeTypes"] || [],
      edgeTypes: options["edgeTypes"] || [],
      direction: options["direction"],
      depth: options["depth"],
      maxNodes: options["maxNodes"],
      scoreThreshold: options["scoreThreshold"]
    }
  end

  defp require_manifest(nil),
    do: {:error, %{code: "graph_not_ready", message: "Graph is not ready."}}

  defp require_manifest(manifest), do: {:ok, manifest}

  def base(ctx, index),
    do: %{
      repoId: ctx.repo["id"],
      ref: ctx.ref,
      resolvedRef: ctx.resolved_ref,
      graphVersion: index["manifest"]["graphVersion"],
      snapshotRoot: snapshot_root(ctx.repo["id"], index["manifest"]["graphVersion"])
    }

  defp snapshot_root(repo_id, graph_version), do: "treedb://graph/#{repo_id}/#{graph_version}"

  defp audit(event_type, ctx, data) do
    TreeDb.Audit.append(event_type, %{
      actor_id: ctx.principal["actorId"],
      tenant_id: ctx.principal["tenantId"],
      repo_id: ctx.repo["id"],
      data: Map.merge(%{ref: ctx.ref, resolvedRef: ctx.resolved_ref}, data)
    })
  end
end
