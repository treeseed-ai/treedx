defmodule TreeDxSdk.SnapshotsAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Snapshots.build(client, "repo/a", %{})
    TreeDxSdk.Snapshots.get(client, "repo/a", "snap/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :get and &1.path == "/api/v1/repos/repo%2Fa/snapshots/snap%2Fa")
           )
  end
end
