defmodule TreeDxSdk.RepositoriesAdapterTest do
  use ExUnit.Case, async: true

  test "register constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Repositories.register(client, %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/repos/register")
           )
  end

  test "get constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Repositories.get(client, "repo/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :get and &1.path == "/api/v1/repos/repo%2Fa")
           )
  end

  test "refs constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Repositories.refs(client, "repo/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :get and &1.path == "/api/v1/repos/repo%2Fa/refs")
           )
  end
end
