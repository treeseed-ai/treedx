defmodule TreeDxSdk.QueryAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Query.read_file(client, "repo/a", %{})
    TreeDxSdk.Query.list_paths(client, "repo/a", %{})
    TreeDxSdk.Query.search_files(client, "repo/a", %{})
    TreeDxSdk.Query.repository(client, "repo/a", %{})

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :post and &1.path == "/api/v1/repos/repo%2Fa/query")
           )
  end
end
