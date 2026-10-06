defmodule TreeDxSdk.MigrationsAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Migrations.create(client, "repo/a", %{})
    TreeDxSdk.Migrations.get(client, "repo/a", "mig/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :get and &1.path == "/api/v1/repos/repo%2Fa/migrations/mig%2Fa")
           )
  end
end
