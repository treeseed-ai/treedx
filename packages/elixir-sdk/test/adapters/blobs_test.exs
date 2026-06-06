defmodule TreeDxSdk.BlobsAdapterTest do
  use ExUnit.Case, async: true

  test "all constructs expected request" do
    {:ok, pid} = TreeDxSdk.Test.MockTransport.start_link()
    client = TreeDxSdk.Test.MockTransport.client(pid)
    TreeDxSdk.Blobs.read(client, "repo/a", %{})
    TreeDxSdk.Blobs.write(client, "ws/a", %{})
    TreeDxSdk.Blobs.download(client, "ws/a")
    TreeDxSdk.Blobs.upload(client, "ws/a", "x")
    TreeDxSdk.Blobs.create_multipart_upload(client, "ws/a", %{})
    TreeDxSdk.Blobs.upload_part(client, "ws/a", "up/a", 2, "x")
    TreeDxSdk.Blobs.complete_multipart_upload(client, "ws/a", "up/a", %{})
    TreeDxSdk.Blobs.abort_multipart_upload(client, "ws/a", "up/a")

    assert Enum.any?(
             TreeDxSdk.Test.MockTransport.requests(pid),
             &(&1.method == :delete and
                 &1.path == "/api/v1/workspaces/ws%2Fa/blobs/uploads/up%2Fa")
           )
  end
end
