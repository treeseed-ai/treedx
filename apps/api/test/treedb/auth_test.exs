defmodule TreeDb.AuthTest do
  use ExUnit.Case, async: false

  setup do
    old_auth = System.get_env("TREEDB_AUTH_MODE")
    old_issuer = System.get_env("TREEDB_JWT_ISSUER")
    old_audience = System.get_env("TREEDB_JWT_AUDIENCE")
    old_secret = System.get_env("TREEDB_JWT_HS256_SECRET")
    System.put_env("TREEDB_AUTH_MODE", "dev")
    dir = Path.join(System.tmp_dir!(), "treedb-auth-test-#{System.unique_integer([:positive])}")
    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDb.Store.seed_dev_records("node_local", "http://localhost:4000")

    on_exit(fn ->
      restore_env("TREEDB_AUTH_MODE", old_auth)
      restore_env("TREEDB_JWT_ISSUER", old_issuer)
      restore_env("TREEDB_JWT_AUDIENCE", old_audience)
      restore_env("TREEDB_JWT_HS256_SECRET", old_secret)
    end)

    :ok
  end

  test "creates and resolves dev token" do
    {:ok, token} = TreeDb.Auth.create_dev_token(%{})
    assert token.accessToken =~ "treedb_dev_"
    assert {:ok, principal} = TreeDb.Auth.authenticate_token(token.accessToken)
    assert principal.actorId == "actor_demo"
  end

  test "expired dev token is rejected" do
    {:ok, token_hash} = TreeDb.Store.hash_token("expired")

    {:ok, _} =
      TreeDb.Store.put_dev_token(%{
        tokenHash: token_hash,
        actorId: "actor_demo",
        tenantId: "tenant_demo",
        expiresAt: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601(),
        createdAt: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    assert {:error, %{code: "token_expired"}} = TreeDb.Auth.authenticate_token("expired")
  end

  test "connected HS256 JWT authenticates and rejects invalid claims" do
    System.put_env("TREEDB_AUTH_MODE", "connected")
    System.put_env("TREEDB_JWT_ISSUER", "https://issuer.example.invalid")
    System.put_env("TREEDB_JWT_AUDIENCE", "treedb")
    System.put_env("TREEDB_JWT_HS256_SECRET", "test-secret")

    token =
      jwt(%{
        "iss" => "https://issuer.example.invalid",
        "aud" => "treedb",
        "sub" => "subject_a",
        "treedb_actor_id" => "actor_demo",
        "treedb_tenant_id" => "tenant_demo",
        "exp" => System.system_time(:second) + 3600,
        "jti" => "jwt_test_1"
      })

    assert {:ok, principal} = TreeDb.Auth.authenticate_token(token)
    assert principal.actorId == "actor_demo"
    assert principal.authMode == "connected"

    expired =
      jwt(%{
        "iss" => "https://issuer.example.invalid",
        "aud" => "treedb",
        "sub" => "subject_a",
        "treedb_tenant_id" => "tenant_demo",
        "exp" => System.system_time(:second) - 120
      })

    assert {:error, %{code: "token_expired"}} = TreeDb.Auth.authenticate_token(expired)

    wrong_issuer =
      jwt(%{
        "iss" => "https://wrong.example.invalid",
        "aud" => "treedb",
        "sub" => "subject_a",
        "treedb_tenant_id" => "tenant_demo",
        "exp" => System.system_time(:second) + 3600
      })

    assert {:error, %{code: "invalid_issuer"}} = TreeDb.Auth.authenticate_token(wrong_issuer)
  end

  defp jwt(payload) do
    header = %{"alg" => "HS256", "typ" => "JWT"} |> Jason.encode!() |> b64()
    body = payload |> Jason.encode!() |> b64()
    signature = :crypto.mac(:hmac, :sha256, "test-secret", "#{header}.#{body}") |> b64()
    "#{header}.#{body}.#{signature}"
  end

  defp b64(bytes), do: Base.url_encode64(bytes, padding: false)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
