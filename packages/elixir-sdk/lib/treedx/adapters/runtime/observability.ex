defmodule TreeDxSdk.Observability do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def health(client) do
    Common.json_request(client, :get, "/api/v1/health", nil, %{})
  end

  def ready(client) do
    Common.json_request(client, :get, "/api/v1/ready", nil, %{})
  end

  def deep_health(client) do
    Common.json_request(client, :get, "/api/v1/health/deep", nil, %{})
  end

  def metrics(client) do
    Common.json_request(client, :get, "/api/v1/metrics", nil, %{})
  end
end
