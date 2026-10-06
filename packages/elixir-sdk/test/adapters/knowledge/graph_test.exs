defmodule TreeDxSdk.GraphAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Graph.refresh(client, "repo/a")
    TreeDxSdk.Graph.query(client, "repo/a", %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/repos/repo%2Fa/graph/query")
           )
  end
end
