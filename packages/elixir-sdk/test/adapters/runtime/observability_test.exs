defmodule TreeDxSdk.ObservabilityAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Observability.health(client)
    TreeDxSdk.Observability.ready(client)
    TreeDxSdk.Observability.deep_health(client)
    TreeDxSdk.Observability.metrics(client)

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :get and &1.path == "/api/v1/metrics")
           )
  end
end
