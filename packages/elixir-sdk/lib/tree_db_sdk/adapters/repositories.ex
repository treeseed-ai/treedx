defmodule TreeDbSdk.Repositories do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def register(client, body) do
    Common.json_request(client, :post, "/api/v1/repos/register", body, %{})
  end

  def list(client) do
    Common.json_request(client, :get, "/api/v1/repos", nil, %{})
  end

  def create(client, body) do
    Common.json_request(client, :post, "/api/v1/repos", body, %{})
  end

  def get(client, repo_id) do
    Common.json_request(client, :get, "/api/v1/repos/" <> Common.segment(repo_id), nil, %{})
  end

  def status(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/status",
      nil,
      %{}
    )
  end

  def refs(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/refs",
      nil,
      %{}
    )
  end

  def remotes(client, repo_id) do
    Common.json_request(
      client,
      :get,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/remotes",
      nil,
      %{}
    )
  end

  def push(client, repo_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/push",
        body
      )

  def sync(client, repo_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/sync",
        body
      )
end
