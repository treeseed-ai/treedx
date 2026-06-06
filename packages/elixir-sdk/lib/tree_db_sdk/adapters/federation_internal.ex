defmodule TreeDbSdk.FederationInternal do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def health(client), do: Common.json_request(client, :get, "/api/v1/internal/federation/health")

  def proxy(client, body),
    do: Common.json_request(client, :post, "/api/v1/internal/federation/proxy", body)

  def export_mirror(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/internal/federation/repos/" <> Common.segment(repo_id) <> "/mirror/export",
        body
      )

  def import_mirror(client, repo_id, body),
    do:
      Common.json_request(
        client,
        :post,
        "/api/v1/internal/federation/repos/" <> Common.segment(repo_id) <> "/mirror/import",
        body
      )
end
