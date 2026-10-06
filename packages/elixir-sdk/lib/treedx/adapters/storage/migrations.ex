defmodule TreeDxSdk.Migrations do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def create(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/migrations",
      body,
      %{}
    )
  end

  def get(client, repo_id, migration_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <>
        Common.segment(repo_id) <> "/migrations/" <> Common.segment(migration_id),
      nil,
      %{}
    )
  end
end
