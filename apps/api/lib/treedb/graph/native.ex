defmodule TreeDb.Graph.Native do
  @moduledoc false

  def build_graph_index(input),
    do: TreeDb.Store.call_json(&TreeDb.Native.build_graph_index/1, Jason.encode!(input))

  def write_graph_segments(index),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.write_graph_segments/2,
        TreeDb.Store.data_dir(),
        Jason.encode!(index)
      )

  def read_graph_segments(repo_id, graph_version),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.read_graph_segments/3,
        TreeDb.Store.data_dir(),
        repo_id,
        graph_version
      )

  def read_latest_graph_manifest(repo_id, ref_name),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.read_latest_graph_manifest/3,
        TreeDb.Store.data_dir(),
        repo_id,
        ref_name
      )

  def search_graph(index, request),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.search_graph/2,
        Jason.encode!(index),
        Jason.encode!(request)
      )

  def query_graph(index, request),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.query_graph/2,
        Jason.encode!(index),
        Jason.encode!(request)
      )

  def related_nodes(index, seed_id, request),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.related_nodes/3,
        Jason.encode!(index),
        seed_id,
        Jason.encode!(request)
      )

  def subgraph(index, seed_ids, request),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.subgraph/3,
        Jason.encode!(index),
        Jason.encode!(seed_ids),
        Jason.encode!(request)
      )

  def build_context_pack(index, request),
    do:
      TreeDb.Store.call_json(
        &TreeDb.Native.build_context_pack/2,
        Jason.encode!(index),
        Jason.encode!(request)
      )

  def parse_ctx_dsl(source), do: TreeDb.Store.call_json(&TreeDb.Native.parse_ctx_dsl/1, source)
end
