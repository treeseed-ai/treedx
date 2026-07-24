defmodule TreeDx.JwksCacheTest do
  use ExUnit.Case, async: false

  setup do
    TreeDx.Auth.JwksCache.reset()
    on_exit(fn -> TreeDx.Auth.JwksCache.reset() end)
    :ok
  end

  test "returns cached key when refresh fails inside grace period" do
    System.put_env("TREEDX_JWKS_CACHE_TTL_SECONDS", "0")
    System.put_env("TREEDX_JWKS_ROTATION_GRACE_SECONDS", "60")

    fetch_ok = fn -> {:ok, [%{"kid" => "kid-a", "kty" => "RSA"}]} end
    assert {:ok, %{"kid" => "kid-a"}} = TreeDx.Auth.JwksCache.get_key("kid-a", fetch_ok)

    fetch_error = fn -> {:error, %{code: "invalid_token", message: "network down"}} end
    assert {:ok, %{"kid" => "kid-a"}} = TreeDx.Auth.JwksCache.get_key("kid-a", fetch_error)
  after
    System.delete_env("TREEDX_JWKS_CACHE_TTL_SECONDS")
    System.delete_env("TREEDX_JWKS_ROTATION_GRACE_SECONDS")
  end
end
