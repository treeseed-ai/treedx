defmodule TreeDx.Federation.Merge do
  @moduledoc false

  @default_limit 20
  @max_limit 100

  def merge(:search, successes, plan, params, errors),
    do:
      wrap(:search, "search", params["query"], successes, plan, params, errors, fn results ->
        sort_results(results, params)
      end)

  def merge(:query, successes, plan, params, errors),
    do:
      wrap(
        :query,
        "query",
        params["type"] || "text",
        successes,
        plan,
        params,
        errors,
        fn results ->
          sort_results(results, params)
        end
      )

  def merge(:context, successes, plan, params, errors) do
    merged =
      %{
        nodes: merge_items(successes, "nodes"),
        edges: merge_items(successes, "edges"),
        files: merge_items(successes, "files"),
        sections: merge_items(successes, "sections")
      }
      |> apply_context_budget(params["budget"] || %{})

    {:ok,
     %{
       context:
         merged
         |> Map.put(:diagnostics, diagnostics(plan, successes, errors))
         |> Map.put(:errors, public_errors(errors))
     }}
  end

  def merge(:graph, successes, plan, params, errors) do
    nodes =
      successes
      |> Enum.flat_map(fn success ->
        success |> get_payload_items("nodes") |> Enum.map(&qualify_node(&1, success))
      end)

    node_ids = MapSet.new(nodes, &get(&1, "id"))

    edges =
      successes
      |> Enum.flat_map(fn success ->
        success |> get_payload_items("edges") |> Enum.map(&qualify_edge(&1, success))
      end)
      |> Enum.filter(
        &(MapSet.member?(node_ids, get(&1, "source")) and
            MapSet.member?(node_ids, get(&1, "target")))
      )

    max_nodes = get_in(params, ["options", "maxNodes"]) || get_in(params, ["options", :maxNodes])

    nodes =
      if is_integer(max_nodes) and max_nodes > 0, do: Enum.take(nodes, max_nodes), else: nodes

    node_ids = MapSet.new(nodes, &get(&1, "id"))

    edges =
      Enum.filter(
        edges,
        &(MapSet.member?(node_ids, get(&1, "source")) and
            MapSet.member?(node_ids, get(&1, "target")))
      )

    {:ok,
     %{
       graph: %{
         nodes: nodes,
         edges: edges,
         diagnostics:
           diagnostics(plan, successes, errors)
           |> Map.put(:crossRepoEdgeCount, cross_repo_edge_count(edges)),
         errors: public_errors(errors)
       }
     }}
  end

  defp wrap(operation, key, value, successes, plan, params, errors, sorter) do
    results =
      successes
      |> Enum.flat_map(fn success ->
        success |> get_payload_items("results") |> Enum.map(&tag_item(&1, success))
      end)
      |> sorter.()

    {page_results, page} = paginate(results, params)

    payload =
      %{
        results: page_results,
        page: page,
        diagnostics: diagnostics(plan, successes, errors),
        errors: public_errors(errors)
      }
      |> Map.put(if(operation == :search, do: :query, else: :type), value)

    {:ok, %{String.to_atom(key) => payload}}
  end

  defp sort_results(results, params) do
    case params["sort"] do
      [%{"field" => field, "direction" => direction} | _] ->
        Enum.sort_by(results, &get(&1, field), sorter(direction))

      _ ->
        Enum.sort_by(results, fn result ->
          {-score(result), get(result, "repoId") || "", get(result, "path") || ""}
        end)
    end
  end

  defp sorter("asc"), do: :asc
  defp sorter(_), do: :desc

  defp score(result) when is_map(result) do
    case get(result, "score") do
      number when is_number(number) -> number
      _ -> 0
    end
  end

  defp paginate(results, params) do
    limit = params["limit"] |> normalize_limit()
    offset = decode_cursor(params["cursor"])
    page_results = results |> Enum.drop(offset) |> Enum.take(limit)
    next_offset = offset + length(page_results)
    has_more = next_offset < length(results)

    page = %{
      limit: limit,
      hasMore: has_more,
      cursor: if(has_more, do: encode_cursor(next_offset), else: nil)
    }

    {page_results, page}
  end

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp normalize_limit(_), do: @default_limit

  defp decode_cursor(nil), do: 0
  defp decode_cursor(""), do: 0

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"offset" => offset, "version" => 1}} <- Jason.decode(json),
         true <- is_integer(offset) and offset >= 0 do
      offset
    else
      _ -> 0
    end
  end

  defp encode_cursor(offset) do
    %{version: 1, offset: offset}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp diagnostics(plan, successes, errors) do
    %{
      requestedRepoCount: length(plan.requestedScope.repoIds),
      executedRepoCount: length(successes),
      rejectedRepoCount: length(plan.rejected),
      partialFailureCount: length(errors),
      routing:
        Enum.map(successes, fn success ->
          %{repoId: success.repoId, nodeId: success.nodeId, source: success.source, status: "ok"}
        end) ++
          Enum.map(errors, fn error ->
            %{
              repoId: error.repoId,
              nodeId: error.nodeId,
              source: error[:source] || error["source"] || "remote",
              status: "partial_failure",
              error: %{code: error.code}
            }
          end)
    }
  end

  defp public_errors(errors) do
    Enum.map(errors, fn error ->
      %{
        repoId: error.repoId,
        nodeId: error.nodeId,
        code: error.code,
        message: error.message
      }
    end)
  end

  defp merge_items(successes, key) do
    Enum.flat_map(successes, fn success ->
      success
      |> get_payload_items(key)
      |> Enum.map(&tag_item(&1, success))
    end)
  end

  defp apply_context_budget(payload, budget) do
    max_nodes = budget["maxNodes"] || budget[:maxNodes]

    if is_integer(max_nodes) and max_nodes > 0 do
      Map.update!(payload, :nodes, &Enum.take(&1, max_nodes))
    else
      payload
    end
  end

  defp get_payload_items(success, key) do
    case get(success.payload, key) do
      items when is_list(items) -> items
      _ -> []
    end
  end

  defp tag_item(item, success) when is_map(item) do
    item
    |> put_if_missing("repoId", success.repoId)
    |> put_if_missing(:repoId, success.repoId)
    |> put_if_missing("ref", success.ref)
    |> put_if_missing(:ref, success.ref)
    |> put_if_missing("source", success.source)
    |> put_if_missing(:source, success.source)
  end

  defp qualify_node(node, success) do
    nested = get(node, "node")
    id = get(node, "id") || get(nested, "id")
    qualified = qualify_id(id, success.repoId, "node")

    node
    |> tag_item(success)
    |> put_value("id", qualified)
    |> maybe_put_nested_id("node", qualified)
  end

  defp qualify_edge(edge, success) do
    nested = get(edge, "edge")

    source =
      get(edge, "source") || get(edge, "sourceId") || get(nested, "source") ||
        get(nested, "sourceId")

    target =
      get(edge, "target") || get(edge, "targetId") || get(nested, "target") ||
        get(nested, "targetId")

    id = get(edge, "id") || get(nested, "id")

    edge
    |> tag_item(success)
    |> put_value("id", qualify_id(id, success.repoId, "edge"))
    |> put_value("source", qualify_id(source, success.repoId, "node"))
    |> put_value("target", qualify_id(target, success.repoId, "node"))
  end

  defp qualify_id("treedx://repo/" <> _ = id, _repo_id, _kind), do: id

  defp qualify_id(id, repo_id, kind) when is_binary(id),
    do: "treedx://repo/#{repo_id}/#{kind}/#{id}"

  defp qualify_id(id, repo_id, kind), do: "treedx://repo/#{repo_id}/#{kind}/#{inspect(id)}"

  defp cross_repo_edge_count(edges) do
    Enum.count(edges, fn edge ->
      repo = get(edge, "repoId")
      source_repo = repo_from_qualified(get(edge, "source"))
      target_repo = repo_from_qualified(get(edge, "target"))

      source_repo && target_repo && source_repo != target_repo &&
        repo in [source_repo, target_repo]
    end)
  end

  defp repo_from_qualified("treedx://repo/" <> rest),
    do: rest |> String.split("/", parts: 2) |> List.first()

  defp repo_from_qualified(_), do: nil

  defp put_if_missing(map, key, value),
    do: if(Map.has_key?(map, key), do: map, else: Map.put(map, key, value))

  defp put_value(map, key, value),
    do: map |> Map.put(key, value) |> Map.put(String.to_atom(key), value)

  defp maybe_put_nested_id(map, key, id) do
    case get(map, key) do
      nested when is_map(nested) ->
        Map.put(map, key, Map.put(nested, "id", id))

      _ ->
        map
    end
  end

  defp get(map, key) when is_map(map) and is_binary(key), do: map[key] || map[String.to_atom(key)]
  defp get(map, key) when is_map(map), do: map[key] || map[to_string(key)]
  defp get(_, _), do: nil
end
