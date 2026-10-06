defmodule TreeDxSdk.FederationAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Federation.plan(client, %{})
    TreeDxSdk.Federation.search(client, %{})
    TreeDxSdk.Federation.query(client, %{})
    TreeDxSdk.Federation.context_build(client, %{})
    TreeDxSdk.Federation.graph_query(client, %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/graph/query")
           )
  end
end
