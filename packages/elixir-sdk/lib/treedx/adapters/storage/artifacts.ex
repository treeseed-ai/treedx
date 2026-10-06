defmodule TreeDxSdk.Artifacts do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def export(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/artifacts/export",
      body,
      %{}
    )
  end

  def list(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/artifacts",
      nil,
      %{}
    )
  end

  def get(client, repo_id, artifact_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/artifacts/" <> Common.segment(artifact_id),
      nil,
      %{}
    )
  end

  def delete(client, repo_id, artifact_id) do
    Common.json_request(
      client,
      :delete,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/artifacts/" <> Common.segment(artifact_id),
      nil,
      %{}
    )
  end
end
