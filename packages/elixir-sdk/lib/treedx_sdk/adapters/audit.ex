defmodule TreeDxSdk.Audit do
  @moduledoc false
  alias TreeDxSdk.Adapters.Common

  def events(client, query \\ %{}),
    do: Common.json_request(client, :get, "/api/v1/audit/events", nil, query)
end
