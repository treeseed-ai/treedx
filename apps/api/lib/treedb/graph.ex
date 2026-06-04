defmodule TreeDb.Graph do
  @moduledoc false

  alias TreeDb.Graph.{Auth, Builder, ContextPack, Dsl, Filter, Native, RefreshJobs}

  def refresh(repo_id, params, principal) do
    with {:ok, ctx} <- Auth.context(repo_id, params, principal, "graph:refresh"),
         {:ok, _} <- TreeDb.Capabilities.require_capability(principal, "files:read", repo_id),
         {:ok, _} <- TreeDb.Capabilities.require_capability(principal, "git:read", repo_id),
         {:ok, previous} <- Native.read_latest_graph_manifest(repo_id, ctx.ref),
         {:ok, refresh_plan} <- refresh_plan(params, previous),
         {:ok, {job, index, manifest, refresh_plan}} <-
           refresh_or_reuse(ctx, params, previous, refresh_plan),
         changed_paths <- authorized_changed_paths(ctx, params),
         indexed_count <- indexed_path_count(refresh_plan.mode, changed_paths, manifest),
         removed_count <- length(manifest["delta"]["removed"] || []),
         {:ok, completed_job} <-
           RefreshJobs.complete(job, manifest["graphVersion"], indexed_count, removed_count) do
      audit("graph.refreshed", ctx, %{
        graphVersion: manifest["graphVersion"],
        refreshMode: refresh_plan.mode,
        changedPathCount: length(changed_paths),
        stale: refresh_plan.stale
      })

      {:ok,
       %{
         ready: true,
         jobId: completed_job["jobId"],
         repoId: repo_id,
         ref: ctx.ref,
         resolvedRef: ctx.resolved_ref,
         graphVersion: manifest["graphVersion"],
         snapshotRoot: snapshot_root(repo_id, manifest["graphVersion"]),
         refreshMode: refresh_plan.mode,
         fallbackReason: refresh_plan.fallback_reason,
         changedPathCount: length(changed_paths),
         indexedPathCount: indexed_count,
         removedPathCount: removed_count,
         stale: refresh_plan.stale,
         changed: manifest["delta"],
         metrics: manifest["metrics"],
         diagnostics: index["diagnostics"]
       }}
    else
      {:error, _error} = result ->
        result

      other ->
        other
    end
  end

  def refresh_job(repo_id, job_id, params, principal),
    do: RefreshJobs.get(repo_id, job_id, params, principal)

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
         {:ok, index} <-
           TreeDb.Graph.IndexCache.get_or_load(ctx.repo["id"], manifest["graphVersion"], fn ->
             Native.read_graph_segments(ctx.repo["id"], manifest["graphVersion"])
           end) do
      {:ok, Filter.authorize(index, ctx.scope, params)}
    end
  end

  defp refresh_or_reuse(ctx, params, previous, refresh_plan) do
    case TreeDb.Graph.RefreshCoordinator.run(ctx, params, previous, refresh_plan, fn ->
           build_refresh(ctx, params, previous, refresh_plan)
         end) do
      {:cached, manifest} ->
        with {:ok, job} <-
               RefreshJobs.start(ctx, params, "cached", nil, false),
             {:ok, index} <-
               TreeDb.Graph.IndexCache.get_or_load(ctx.repo["id"], manifest["graphVersion"], fn ->
                 Native.read_graph_segments(ctx.repo["id"], manifest["graphVersion"])
               end) do
          {:ok, {job, index, manifest, %{refresh_plan | mode: "cached"}}}
        end

      {:cached_stale, manifest} ->
        with {:ok, job} <-
               RefreshJobs.start(ctx, params, "cached", "dedupe_timeout", true),
             {:ok, index} <-
               TreeDb.Graph.IndexCache.get_or_load(ctx.repo["id"], manifest["graphVersion"], fn ->
                 Native.read_graph_segments(ctx.repo["id"], manifest["graphVersion"])
               end) do
          {:ok,
           {job, index, manifest,
            %{refresh_plan | mode: "cached", fallback_reason: "dedupe_timeout", stale: true}}}
        end

      other ->
        other
    end
  end

  defp build_refresh(ctx, params, previous, refresh_plan) do
    with {:ok, job} <-
           RefreshJobs.start(
             ctx,
             params,
             refresh_plan.mode,
             refresh_plan.fallback_reason,
             refresh_plan.stale
           ),
         {:ok, input} <- Builder.build_input(ctx, params, previous),
         {:ok, index} <- Native.build_graph_index(input),
         {:ok, manifest} <- Native.write_graph_segments(index),
         :ok <- TreeDb.Graph.IndexCache.put(index) do
      {:ok, {job, index, manifest, refresh_plan}}
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

  defp refresh_plan(params, previous) do
    changed_paths = list_param(params["changedPaths"])
    incremental? = params["incremental"] != false and params["forceFull"] != true
    max_changed = graph_incremental_max_changed_paths()
    base = params["baseGraphVersion"]
    stale = is_binary(base) and is_map(previous) and previous["graphVersion"] != base

    cond do
      !incremental? ->
        {:ok, %{mode: "full", fallback_reason: nil, stale: stale}}

      previous in [nil, %{}] ->
        {:ok, %{mode: "full", fallback_reason: "missing_base_graph", stale: false}}

      stale ->
        {:ok, %{mode: "full", fallback_reason: "stale_base_graph", stale: true}}

      length(changed_paths) > max_changed ->
        {:ok, %{mode: "full", fallback_reason: "changed_path_limit_exceeded", stale: false}}

      changed_paths == [] ->
        {:ok, %{mode: "full", fallback_reason: "changed_paths_empty", stale: false}}

      true ->
        {:ok, %{mode: "incremental", fallback_reason: nil, stale: false}}
    end
  end

  defp authorized_changed_paths(ctx, params) do
    params["changedPaths"]
    |> list_param()
    |> Enum.filter(fn path ->
      match?(:ok, TreeDb.Capabilities.require_paths(ctx.scope, [path]))
    end)
  end

  defp indexed_path_count("incremental", changed_paths, _manifest), do: length(changed_paths)

  defp indexed_path_count(_mode, _changed_paths, manifest),
    do: manifest["documentCount"] || get_in(manifest, ["metrics", "totalFiles"]) || 0

  defp list_param(nil), do: []
  defp list_param(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp list_param(value) when is_binary(value), do: [value]

  defp graph_incremental_max_changed_paths do
    System.get_env("TREEDB_GRAPH_INCREMENTAL_MAX_CHANGED_PATHS", "500")
    |> String.to_integer()
  rescue
    _ -> 500
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
