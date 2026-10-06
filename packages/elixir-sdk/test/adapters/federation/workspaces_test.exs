defmodule TreeDxSdk.WorkspacesAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Workspaces.create(client, "repo/a", %{})
    TreeDxSdk.Workspaces.get(client, "ws/a")
    TreeDxSdk.Workspaces.close(client, "ws/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/workspaces/ws%2Fa/close")
           )
  end
end
