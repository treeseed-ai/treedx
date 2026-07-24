defmodule TreeDxSdk.RegistryAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Registry.local_node(client)
    TreeDxSdk.Registry.nodes(client)
    TreeDxSdk.Registry.get_placement(client, "repo/a")
    TreeDxSdk.Registry.set_placement(client, "repo/a", %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/registry/repos/repo%2Fa/placement")
           )
  end
end
