defmodule TreeDx.AuthVerifierTest do
  use ExUnit.Case, async: false

  setup do
    old_env = snapshot_env()

    dir =
      Path.join(
        System.tmp_dir!(),
        "treedx-auth-verifier-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")
    TreeDx.Auth.JwksCache.reset()

    on_exit(fn ->
      restore_env(old_env)
      TreeDx.Auth.JwksCache.reset()
    end)

    :ok
  end

  test "connected mode refuses missing verifier config" do
    System.put_env("TREEDX_AUTH_MODE", "connected")
    System.delete_env("TREEDX_AUTH_VERIFIER")
    System.delete_env("TREEDX_JWT_HS256_SECRET")

    assert {:error, %{code: "auth_not_configured"}} = TreeDx.Auth.validate_boot_config()
  end

  test "hs256_dev verifier remains compatible" do
    configure_hs256!()

    token =
      hs256_jwt(%{
        "iss" => "https://issuer.example.invalid",
        "aud" => "treedx",
        "sub" => "subject_a",
        "treedx_actor_id" => "actor_demo",
        "treedx_tenant_id" => "tenant_demo",
        "exp" => System.system_time(:second) + 3600
      })

    assert {:ok, principal} = TreeDx.Auth.authenticate_token(token)
    assert principal.actorId == "actor_demo"
  end

  test "jwks_oidc verifies RS256 tokens, refreshes rotated keys, and rejects unsupported algs" do
    {private_a, jwk_a} = rsa_jwk("kid-a")
    {private_b, jwk_b} = rsa_jwk("kid-b")
    jwks_path = Path.join(TreeDx.Store.data_dir(), "jwks.json")
    File.write!(jwks_path, Jason.encode!(%{"keys" => [jwk_a]}))

    configure_jwks!(jwks_path)

    token_a = rs256_jwt(private_a, "kid-a", valid_claims())
    assert {:ok, principal} = TreeDx.Auth.authenticate_token(token_a)
    assert principal.actorId == "actor_demo"

    File.write!(jwks_path, Jason.encode!(%{"keys" => [jwk_a, jwk_b]}))
    token_b = rs256_jwt(private_b, "kid-b", valid_claims())
    assert {:ok, _principal} = TreeDx.Auth.authenticate_token(token_b)

    unsigned =
      [
        b64(%{"alg" => "none", "typ" => "JWT"}),
        b64(valid_claims()),
        ""
      ]
      |> Enum.join(".")

    assert {:error, %{code: "invalid_token"}} = TreeDx.Auth.authenticate_token(unsigned)
  end

  test "jwks_oidc rejects missing exp, wrong issuer, wrong audience, and malformed jwks" do
    {private_key, jwk} = rsa_jwk("kid-a")
    jwks_path = Path.join(TreeDx.Store.data_dir(), "jwks.json")
    File.write!(jwks_path, Jason.encode!(%{"keys" => [jwk]}))
    configure_jwks!(jwks_path)

    assert {:error, %{code: "invalid_token"}} =
             TreeDx.Auth.authenticate_token(
               rs256_jwt(private_key, "kid-a", Map.delete(valid_claims(), "exp"))
             )

    assert {:error, %{code: "invalid_issuer"}} =
             TreeDx.Auth.authenticate_token(
               rs256_jwt(private_key, "kid-a", Map.put(valid_claims(), "iss", "wrong"))
             )

    assert {:error, %{code: "invalid_audience"}} =
             TreeDx.Auth.authenticate_token(
               rs256_jwt(private_key, "kid-a", Map.put(valid_claims(), "aud", "wrong"))
             )

    TreeDx.Auth.JwksCache.reset()
    File.write!(jwks_path, Jason.encode!(%{"bad" => []}))

    assert {:error, %{code: "invalid_token"}} =
             TreeDx.Auth.authenticate_token(rs256_jwt(private_key, "kid-a", valid_claims()))
  end

  defp configure_hs256! do
    System.put_env("TREEDX_AUTH_MODE", "connected")
    System.put_env("TREEDX_AUTH_VERIFIER", "hs256_dev")
    System.put_env("TREEDX_JWT_ISSUER", "https://issuer.example.invalid")
    System.put_env("TREEDX_JWT_AUDIENCE", "treedx")
    System.put_env("TREEDX_JWT_HS256_SECRET", "test-secret")
  end

  defp configure_jwks!(path) do
    System.put_env("TREEDX_AUTH_MODE", "connected")
    System.put_env("TREEDX_AUTH_VERIFIER", "jwks_oidc")
    System.put_env("TREEDX_JWT_ISSUER", "https://issuer.example.invalid")
    System.put_env("TREEDX_JWT_AUDIENCE", "treedx")
    System.put_env("TREEDX_JWKS_URL", "file://#{path}")
    System.put_env("TREEDX_JWT_ALLOWED_ALGS", "RS256")
  end

  defp valid_claims do
    %{
      "iss" => "https://issuer.example.invalid",
      "aud" => "treedx",
      "sub" => "subject_a",
      "treedx_actor_id" => "actor_demo",
      "treedx_tenant_id" => "tenant_demo",
      "exp" => System.system_time(:second) + 3600
    }
  end

  defp hs256_jwt(payload) do
    header = b64(%{"alg" => "HS256", "typ" => "JWT"})
    body = b64(payload)

    signature =
      :crypto.mac(:hmac, :sha256, "test-secret", "#{header}.#{body}")
      |> Base.url_encode64(padding: false)

    "#{header}.#{body}.#{signature}"
  end

  defp rs256_jwt(private_key, kid, payload) do
    header = b64(%{"alg" => "RS256", "typ" => "JWT", "kid" => kid})
    body = b64(payload)

    signature =
      :public_key.sign("#{header}.#{body}", :sha256, private_key)
      |> Base.url_encode64(padding: false)

    "#{header}.#{body}.#{signature}"
  end

  defp rsa_jwk(kid) do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    modulus = elem(private_key, 2)
    exponent = elem(private_key, 3)

    {private_key,
     %{
       "kty" => "RSA",
       "kid" => kid,
       "alg" => "RS256",
       "use" => "sig",
       "n" => :binary.encode_unsigned(modulus) |> Base.url_encode64(padding: false),
       "e" => :binary.encode_unsigned(exponent) |> Base.url_encode64(padding: false)
     }}
  end

  defp b64(payload), do: payload |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp snapshot_env do
    for name <- env_names(), into: %{}, do: {name, System.get_env(name)}
  end

  defp restore_env(env) do
    for name <- env_names() do
      case env[name] do
        nil -> System.delete_env(name)
        value -> System.put_env(name, value)
      end
    end
  end

  defp env_names do
    ~w[
      TREEDX_AUTH_MODE
      TREEDX_AUTH_VERIFIER
      TREEDX_JWT_ISSUER
      TREEDX_JWT_AUDIENCE
      TREEDX_JWT_HS256_SECRET
      TREEDX_JWKS_URL
      TREEDX_JWT_ALLOWED_ALGS
    ]
  end
end
