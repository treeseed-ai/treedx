defmodule TreeDxSdk.FilesAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Files.tree(client, "ws/a")
    TreeDxSdk.Files.write(client, "ws/a", %{})
    TreeDxSdk.Files.patch(client, "ws/a", %{})
    TreeDxSdk.Files.delete(client, "ws/a")
    TreeDxSdk.Files.commit(client, "ws/a", %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/workspaces/ws%2Fa/commit")
           )
  end
end
