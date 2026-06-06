defmodule TreeDbSdk.Graph do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def refresh(client, repo_id, body \\ %{}) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/refresh",
      body,
      %{}
    )
  end

  def query(client, repo_id, body) do
    Common.json_request(
      client,
      :post,
      "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/query",
      body,
      %{}
    )
  end

  def refresh_job(client, repo_id, job_id),
    do:
      Common.json_request(
        client,
        :get,
        "/api/v1/repos/" <>
          Common.segment(repo_id) <> "/graph/refresh-jobs/" <> Common.segment(job_id)
      )

  def node(client, repo_id, node_id, query \\ %{}),
    do:
      Common.json_request(
        client,
        :get,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/nodes/" <> Common.segment(node_id),
        nil,
        query
      )

  def related(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/related",
        body
      )

  def subgraph(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/subgraph",
        body
      )

  def search_files(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/search-files",
        body
      )

  def search_sections(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/search-sections",
        body
      )

  def search_entities(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/repos/" <> Common.segment(repo_id) <> "/graph/search-entities",
        body
      )
end
