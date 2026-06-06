defmodule TreeDxSdk.Generated.ExportsTest do
  use ExUnit.Case, async: true

  test "public modules compile" do
    assert is_list(TreeDxSdk.Generated.OpenApiTypes.operations())
    assert %TreeDxSdk.Error{} = TreeDxSdk.Error.network("offline")
    client = TreeDxSdk.Client.new(base_url: "http://localhost:4000")
    assert %TreeDxSdk.Conformance.Adapter{} = TreeDxSdk.Conformance.Adapter.new(client)
  end
end
