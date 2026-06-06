defmodule TreeDxSdk.Workspaces do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def create(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/workspaces",
      body,
      %{}
    )
  end

  def get(client, workspace_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id),
      nil,
      %{}
    )
  end

  def close(client, workspace_id, body \\ %{}) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/close",
      body,
      %{}
    )
  end
end
