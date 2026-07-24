defmodule TreeDxSdk.Snapshots do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def build(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/snapshots/build",
      body,
      %{}
    )
  end

  def get(client, repo_id, snapshot_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/snapshots/" <> Common.segment(snapshot_id),
      nil,
      %{}
    )
  end
end
