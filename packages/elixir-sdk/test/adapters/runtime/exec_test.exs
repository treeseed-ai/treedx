defmodule TreeDxSdk.ExecAdapterTest do
  use ExUnit.Case, async: true

  test "run constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Exec.run(client, "ws/a", %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/workspaces/ws%2Fa/exec")
           )
  end
end
