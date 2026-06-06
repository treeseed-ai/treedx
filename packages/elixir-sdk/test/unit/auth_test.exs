defmodule TreeDxSdk.AuthTest do
  use ExUnit.Case, async: true

  test "static bearer auth resolves authorization header" do
    config = %TreeDxSdk.Config{token: "secret"}

    assert {:ok, {"Authorization", "Bearer secret"}} =
             TreeDxSdk.Auth.resolve_authorization_header(config)
  end
end
