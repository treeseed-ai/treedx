defmodule TreeDxSdk.Registry do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def local_node(client) do
    Common.json_request(client, :get, "/api/v1/node", nil, %{})
  end

  def nodes(client) do
    Common.json_request(client, :get, "/api/v1/registry/nodes", nil, %{})
  end

  def get_placement(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/registry/repos/" <> Common.segment(repo_id) <> "/placement",
      nil,
      %{}
    )
  end

  def set_placement(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/registry/repos/" <> Common.segment(repo_id) <> "/placement",
      body,
      %{}
    )
  end
end
