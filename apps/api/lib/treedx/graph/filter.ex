defmodule TreeDx.Graph.Filter do
  @moduledoc false

  alias TreeDx.Files.PathPolicy

  def authorize(index, scope, params) do
    allow_protected = params["allowProtected"] in [true, "true", "1", 1]

    allowed_ids =
      index["nodes"]
      |> Enum.filter(&allowed_node?(&1, scope, allow_protected))
      |> MapSet.new(& &1["id"])

    edges =
      Enum.filter(index["edges"], fn edge ->
        MapSet.member?(allowed_ids, edge["sourceId"]) and
          MapSet.member?(allowed_ids, edge["targetId"])
      end)

    connected_ids =
      edges
      |> Enum.flat_map(&[&1["sourceId"], &1["targetId"]])
      |> MapSet.new()

    nodes =
      Enum.filter(index["nodes"], fn node ->
        MapSet.member?(allowed_ids, node["id"]) and
          (is_binary(node["path"]) or MapSet.member?(connected_ids, node["id"]))
      end)

    index
    |> Map.put("nodes", nodes)
    |> Map.put("edges", edges)
    |> put_in(["manifest", "nodeCount"], length(nodes))
    |> put_in(["manifest", "edgeCount"], length(edges))
  end

  defp allowed_node?(%{"path" => path}, scope, allow_protected) when is_binary(path) do
    (allow_protected or !PathPolicy.protected?(path)) and
      match?(:ok, TreeDx.Capabilities.require_paths(scope, [path]))
  end

  defp allowed_node?(_node, _scope, _allow_protected), do: true
end
