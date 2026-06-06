defmodule TreeDx.Registry do
  @moduledoc false

  def node do
    node_id = System.get_env("TREEDX_NODE_ID") || "node_local"
    TreeDx.Store.get_node(node_id)
  end

  def nodes, do: TreeDx.Store.list_nodes()
  def placement(repo_id), do: TreeDx.Store.get_repository_placement(repo_id)
  def put_placement(input), do: TreeDx.Store.put_repository_placement(input)
  def mirrors(repo_id), do: TreeDx.Store.list_mirrors(repo_id)
  def put_mirror(input), do: TreeDx.Store.put_mirror(input)
end
