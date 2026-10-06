defmodule TreeDxSdk.Blobs do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def read(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/blobs/read",
      body,
      %{}
    )
  end

  def write(client, workspace_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/blobs/write",
      body,
      %{}
    )
  end

  def delete(client, workspace_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/blobs/delete",
      body,
      %{}
    )
  end

  def download(client, workspace_id, query \\ %{}) do
    Common.json_request(
      client,
      :get,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/blobs/download",
      nil,
      query
    )
  end

  def upload(client, workspace_id, binary_body, query \\ %{}) do
    Common.binary_request(
      client,
      :put,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/blobs/upload",
      binary_body,
      query
    )
  end

  def create_multipart_upload(client, workspace_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <> Common.segment(workspace_id) <> "/blobs/uploads",
      body,
      %{}
    )
  end

  def upload_part(client, workspace_id, upload_id, part_number, binary_body) do
    Common.binary_request(
      client,
      :put,
      "/api/v1/workspaces/" <>
        Common.segment(workspace_id) <>
        "/blobs/uploads/" <> Common.segment(upload_id) <> "/parts/" <> Common.segment(part_number),
      binary_body,
      %{}
    )
  end

  def complete_multipart_upload(client, workspace_id, upload_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/workspaces/" <>
        Common.segment(workspace_id) <>
        "/blobs/uploads/" <> Common.segment(upload_id) <> "/complete",
      body,
      %{}
    )
  end

  def abort_multipart_upload(client, workspace_id, upload_id) do
    Common.json_request(
      client,
      :delete,
      "/api/v1/workspaces/" <>
        Common.segment(workspace_id) <> "/blobs/uploads/" <> Common.segment(upload_id),
      nil,
      %{}
    )
  end
end
