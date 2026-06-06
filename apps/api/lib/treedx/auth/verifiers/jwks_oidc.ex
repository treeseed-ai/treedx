defmodule TreeDx.Auth.Verifiers.JwksOidc do
  @moduledoc false

  alias TreeDx.Auth.Verifiers.Hs256Dev

  def validate_config do
    required = [
      {"TREEDX_JWT_ISSUER", Hs256Dev.issuer()},
      {"TREEDX_JWT_AUDIENCE", Hs256Dev.audience()},
      {"TREEDX_JWKS_URL", System.get_env("TREEDX_JWKS_URL")}
    ]

    case Enum.filter(required, fn {_name, value} -> !is_binary(value) or value == "" end) do
      [] ->
        :ok

      missing ->
        names = Enum.map_join(missing, ", ", &elem(&1, 0))
        {:error, %{code: "auth_not_configured", message: "Missing JWKS auth config: #{names}."}}
    end
  end

  def verify(token) when is_binary(token) do
    with :ok <- validate_config(),
         [header64, payload64, signature64] <- String.split(token, "."),
         {:ok, header} <- Hs256Dev.decode_json64(header64),
         {:ok, claims} <- Hs256Dev.decode_json64(payload64),
         :ok <- require_alg(header),
         {:ok, kid} <- require_kid(header),
         {:ok, jwk} <- TreeDx.Auth.JwksCache.get_key(kid),
         :ok <- verify_signature("#{header64}.#{payload64}", signature64, jwk),
         :ok <- Hs256Dev.verify_common_claims(claims) do
      {:ok, claims}
    else
      [_one, _two] -> Hs256Dev.invalid()
      [_one] -> Hs256Dev.invalid()
      [] -> Hs256Dev.invalid()
      {:error, error} -> {:error, error}
      _ -> Hs256Dev.invalid()
    end
  end

  def verify(_), do: Hs256Dev.invalid()

  def info,
    do: %{
      type: "jwks_oidc",
      issuer: Hs256Dev.issuer(),
      jwksUrl: redact_url(System.get_env("TREEDX_JWKS_URL"))
    }

  defp require_alg(%{"alg" => alg}) do
    allowed = allowed_algs()

    cond do
      alg == "none" ->
        {:error, %{code: "invalid_token", message: "Unsigned tokens are not supported."}}

      alg == "HS256" ->
        {:error, %{code: "invalid_token", message: "HS256 is not supported by jwks_oidc."}}

      alg in allowed ->
        :ok

      true ->
        {:error, %{code: "invalid_token", message: "JWT alg is not allowed."}}
    end
  end

  defp require_alg(_), do: {:error, %{code: "invalid_token", message: "JWT alg is required."}}

  defp require_kid(%{"kid" => kid}) when is_binary(kid) and kid != "", do: {:ok, kid}
  defp require_kid(_), do: {:error, %{code: "invalid_token", message: "JWT kid is required."}}

  defp verify_signature(signing_input, signature64, %{"kty" => "RSA", "n" => n64, "e" => e64}) do
    with {:ok, signature} <- Base.url_decode64(signature64, padding: false),
         {:ok, modulus} <- decode_uint(n64),
         {:ok, exponent} <- decode_uint(e64) do
      key = {:RSAPublicKey, modulus, exponent}

      if :public_key.verify(signing_input, :sha256, signature, key) do
        :ok
      else
        {:error, %{code: "invalid_signature", message: "Invalid bearer token signature."}}
      end
    else
      _ -> {:error, %{code: "invalid_token", message: "Invalid JWKS key material."}}
    end
  end

  defp verify_signature(_signing_input, _signature64, _jwk),
    do: {:error, %{code: "invalid_token", message: "Unsupported JWKS key."}}

  defp decode_uint(value) do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false) do
      {:ok, :binary.decode_unsigned(bytes)}
    end
  end

  defp allowed_algs do
    (System.get_env("TREEDX_JWT_ALLOWED_ALGS") || "RS256")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end

  defp redact_url(nil), do: nil
  defp redact_url("file://" <> _), do: "file://redacted"

  defp redact_url(url) do
    uri = URI.parse(url)
    %URI{uri | query: nil, userinfo: nil} |> URI.to_string()
  end
end
