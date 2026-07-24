defmodule TreeDxSdk.Context do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def build(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/context/build",
      body,
      %{}
    )
  end

  def parse(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/context/parse-ctx",
      body,
      %{}
    )
  end
end
