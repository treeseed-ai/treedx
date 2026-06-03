defmodule TreeDb.Federation.Router do
  @moduledoc false

  def route(node_id) do
    local_node = System.get_env("TREEDB_NODE_ID") || "node_local"

    if node_id == local_node do
      %{source: "local", base_url: nil}
    else
      case remote_node(node_id) do
        {:ok, node} -> %{source: "remote", base_url: node["baseUrl"]}
        {:error, _} -> %{source: "remote", base_url: nil}
      end
    end
  end

  def remote_node(node_id) do
    TreeDb.Registry.nodes()
    |> case do
      {:ok, nodes} ->
        case Enum.find(nodes, &(&1["id"] == node_id)) do
          nil -> {:error, %{code: "federated_route_not_configured"}}
          node -> {:ok, node}
        end

      _ ->
        {:error, %{code: "federated_route_not_configured"}}
    end
  end
end
