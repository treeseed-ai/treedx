defmodule TreeDxSdk.BinaryTest do
  use ExUnit.Case, async: true

  test "binary helpers accept binaries and iodata" do
    assert TreeDxSdk.Binary.binary_body?("abc")
    assert TreeDxSdk.Binary.to_binary(["a", "b"]) == "ab"
  end

  test "binary helpers reject maps" do
    refute TreeDxSdk.Binary.binary_body?(%{})
    assert_raise ArgumentError, fn -> TreeDxSdk.Binary.assert_binary_body!(%{}) end
  end
end
