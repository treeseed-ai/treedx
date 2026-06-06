defmodule TreeDbSdk.Policy do
  @moduledoc false
  alias TreeDbSdk.Adapters.Common

  def capabilities(client), do: Common.json_request(client, :get, "/api/v1/policy/capabilities")

  def grants(client, query \\ %{}),
    do: Common.json_request(client, :get, "/api/v1/policy/grants", nil, query)

  def create_grant(client, body),
    do: Common.json_request(client, :post, "/api/v1/policy/grants", body)

  def refresh(client, body \\ %{}),
    do: Common.json_request(client, :post, "/api/v1/policy/refresh", body)
end
