defmodule TreeDxSdk.Query do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def read_file(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/files/read",
      body,
      %{}
    )
  end

  def list_paths(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/paths/list",
      body,
      %{}
    )
  end

  def search_files(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/files/search",
      body,
      %{}
    )
  end

  def repository(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/query",
      body,
      %{}
    )
  end
end
