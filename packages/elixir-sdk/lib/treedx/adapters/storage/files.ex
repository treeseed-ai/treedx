defmodule TreeDxSdk.Files do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def tree(client, workspace_id, query \\ %{}) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/tree",
      nil,
      query
    )
  end

  def read(client, workspace_id, query \\ %{}) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/files",
      nil,
      query
    )
  end

  def write(client, workspace_id, body) do
    Common.json_request(
      client,
      :put,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/files",
      body,
      %{}
    )
  end

  def patch(client, workspace_id, body) do
    Common.json_request(
      client,
      :patch,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/files",
      body,
      %{}
    )
  end

  def delete(client, workspace_id, query \\ %{}) do
    Common.json_request(
      client,
      :delete,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/files",
      nil,
      query
    )
  end

  def search(client, workspace_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/search",
      body,
      %{}
    )
  end

  def status(client, workspace_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/status",
      nil,
      %{}
    )
  end

  def diff(client, workspace_id, query \\ %{}) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/diff",
      nil,
      query
    )
  end

  def commit(client, workspace_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/commit",
      body,
      %{}
    )
  end
end
