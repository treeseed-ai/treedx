defmodule TreeDbSdk.SearchIndex do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def status(client, repo_id, query \\ %{}),
    do:
      Common.json_request(
        client,
        :get,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/search/index/status",
        nil,
        query
      )

  def refresh(client, repo_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/search/index/refresh",
        body
      )

  def compact(client, repo_id, body \\ %{}),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/search/index/compact",
        body
      )
end
