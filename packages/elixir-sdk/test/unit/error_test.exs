defmodule TreeDxSdk.ErrorTest do
  use ExUnit.Case, async: true

  test "from_response preserves envelope fields" do
    payload = %{
      "error" => %{
        "code" => "invalid_token",
        "message" => "bad",
        "details" => %{"why" => "expired"}
      }
    }

    error = TreeDxSdk.Error.from_response(401, payload)
    assert error.status == 401
    assert error.code == "invalid_token"
    assert error.message == "bad"
    assert error.details == %{"why" => "expired"}
    assert error.payload == payload
  end

  test "network error uses stable code" do
    error = TreeDxSdk.Error.network("offline")
    assert error.status == 0
    assert error.code == "network_error"
  end
end
