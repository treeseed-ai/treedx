defmodule TreeDxSdk.ClientTest do
  use ExUnit.Case, async: true

  test "client preserves config and custom transport" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    assert client.config.base_url == "http://localhost:4000"
    assert client.config.transport == {TreeDxSdk.Test.MockTransport, pid}
  end

  test "top-level health delegates through transport" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    assert {:ok, %{"ok" => true}} = TreeDxSdk.health(client)
    assert [%{path: "/api/v1/health"}] = TreeDxSdk.Test.MockTransport.requests(pid)
  end
end
