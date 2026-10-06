defmodule TreeDxSdk.MirrorsAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Mirrors.list(client, "repo/a")
    TreeDxSdk.Mirrors.upsert(client, "repo/a", %{})
    TreeDxSdk.Mirrors.sync(client, "repo/a", "mir/a")
    TreeDxSdk.Mirrors.health(client, "repo/a", "mir/a")
    TreeDxSdk.Mirrors.promote(client, "repo/a", "mir/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/repos/repo%2Fa/mirrors/mir%2Fa/promote")
           )
  end
end
