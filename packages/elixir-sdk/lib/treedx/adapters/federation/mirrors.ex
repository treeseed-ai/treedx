defmodule TreeDxSdk.Mirrors do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def list(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/mirrors",
      nil,
      %{}
    )
  end

  def upsert(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/mirrors",
      body,
      %{}
    )
  end

  def sync(client, repo_id, mirror_id, body \\ %{}) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <>
        Common.segment(repo_id) <> "/mirrors/" <> Common.segment(mirror_id) <> "/sync",
      body,
      %{}
    )
  end

  def health(client, repo_id, mirror_id, body \\ %{}) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <>
        Common.segment(repo_id) <> "/mirrors/" <> Common.segment(mirror_id) <> "/health",
      body,
      %{}
    )
  end

  def promote(client, repo_id, mirror_id, body \\ %{}) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <>
        Common.segment(repo_id) <> "/mirrors/" <> Common.segment(mirror_id) <> "/promote",
      body,
      %{}
    )
  end
end
