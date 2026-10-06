defmodule TreeDxSdk.Federation do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def plan(client, body) do
    Common.json_request(client, :post, "/api/v1/federation/query/plan", body, %{})
  end

  def search(client, body) do
    Common.json_request(client, :post, "/api/v1/search", body, %{})
  end

  def query(client, body) do
    Common.json_request(client, :post, "/api/v1/query", body, %{})
  end

  def context_build(client, body) do
    Common.json_request(client, :post, "/api/v1/context/build", body, %{})
  end

  def graph_query(client, body) do
    Common.json_request(client, :post, "/api/v1/graph/query", body, %{})
  end

  def catalog(client), do: Common.json_request(client, :get, "/api/v1/federation/catalog")

  def push_catalog(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/federation/catalog/push", body)

  def sync_catalog(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/federation/catalog/sync", body)

  def peers(client), do: Common.json_request(client, :get, "/api/v1/federation/peers")

  def peer(client, node_id),
    do: Common.json_request(client, :get, "/api/v1/federation/peers/" <> Common.segment(node_id))

  def register_node(client, body),
    do: Common.json_request(client, :post, "/api/v1/federation/nodes/register", body)

  def trust_peer(client, node_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/federation/peers/" <> Common.segment(node_id) <> "/trust",
        body
      )

  def revoke_peer(client, node_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/federation/peers/" <> Common.segment(node_id) <> "/revoke",
        body
      )

  def routes(client), do: Common.json_request(client, :get, "/api/v1/federation/routes")
end
