defmodule TreeDxSdk.ArtifactsAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Artifacts.export(client, "repo/a", %{})
    TreeDxSdk.Artifacts.list(client, "repo/a")
    TreeDxSdk.Artifacts.get(client, "repo/a", "art/a")
    TreeDxSdk.Artifacts.delete(client, "repo/a", "art/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :delete and &1.path == "/api/v1/repos/repo%2Fa/artifacts/art%2Fa")
           )
  end
end
