defmodule TreeDxSdk.LiveApiTest do
  use ExUnit.Case, async: true

  test "live health is optional" do
    case System.get_env("TREEDX_BASE_URL") do
      nil ->
        assert true

      base_url ->
        client = TreeDxSdk.Client.new(base_url: base_url, token: System.get_env("TREEDX_TOKEN"))
        assert {:ok, _} = TreeDxSdk.health(client)
    end
  end
end
