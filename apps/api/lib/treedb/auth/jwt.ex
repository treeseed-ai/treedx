defmodule TreeDb.Auth.Jwt do
  @moduledoc false

  @default_skew 60

  def validate_config do
    required = [
      {"TREEDB_JWT_ISSUER", issuer()},
      {"TREEDB_JWT_AUDIENCE", audience()},
      {"TREEDB_JWT_HS256_SECRET", secret()}
    ]

    case Enum.filter(required, fn {_name, value} -> !is_binary(value) or value == "" end) do
      [] ->
        :ok

      missing ->
        names = Enum.map_join(missing, ", ", &elem(&1, 0))

        {:error,
         %{code: "auth_not_configured", message: "Missing connected auth config: #{names}."}}
    end
  end

  def verify(token) when is_binary(token) do
    with :ok <- validate_config(),
         [header64, payload64, signature64] <- String.split(token, "."),
         {:ok, header} <- decode_json64(header64),
         {:ok, claims} <- decode_json64(payload64),
         :ok <- require_alg(header),
         :ok <- verify_signature("#{header64}.#{payload64}", signature64),
         :ok <- verify_issuer(claims),
         :ok <- verify_audience(claims),
         :ok <- verify_time(claims) do
      {:ok, claims}
    else
      [_one, _two] -> invalid()
      [_one] -> invalid()
      [] -> invalid()
      {:error, error} -> {:error, error}
      error when is_map(error) -> {:error, error}
      _ -> invalid()
    end
  end

  def verify(_), do: invalid()

  def verifier_info do
    %{type: "jwt_hs256", issuer: issuer()}
  end

  defp require_alg(%{"alg" => "HS256"}), do: :ok
  defp require_alg(_), do: {:error, %{code: "invalid_token", message: "JWT alg must be HS256."}}

  defp verify_signature(signing_input, signature64) do
    expected =
      :crypto.mac(:hmac, :sha256, secret(), signing_input)
      |> Base.url_encode64(padding: false)

    if secure_compare(expected, signature64) do
      :ok
    else
      {:error, %{code: "invalid_signature", message: "Invalid bearer token signature."}}
    end
  end

  defp verify_issuer(%{"iss" => value}) do
    if value == issuer(), do: :ok, else: invalid_issuer()
  end

  defp verify_issuer(_), do: invalid_issuer()

  defp invalid_issuer,
    do: {:error, %{code: "invalid_issuer", message: "Invalid token issuer."}}

  defp verify_audience(%{"aud" => value}) when is_binary(value) do
    if value == audience(), do: :ok, else: invalid_audience()
  end

  defp verify_audience(%{"aud" => values}) when is_list(values) do
    if audience() in values, do: :ok, else: invalid_audience()
  end

  defp verify_audience(_), do: invalid_audience()

  defp invalid_audience,
    do: {:error, %{code: "invalid_audience", message: "Invalid token audience."}}

  defp verify_time(claims) do
    now = System.system_time(:second)
    skew = clock_skew()

    cond do
      is_number(claims["exp"]) and claims["exp"] + skew <= now ->
        {:error, %{code: "token_expired", message: "Token has expired."}}

      is_number(claims["nbf"]) and claims["nbf"] - skew > now ->
        {:error, %{code: "token_not_yet_valid", message: "Token is not valid yet."}}

      !is_number(claims["exp"]) ->
        {:error, %{code: "invalid_token", message: "Token exp claim is required."}}

      true ->
        :ok
    end
  end

  defp decode_json64(value) do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false),
         {:ok, decoded} <- Jason.decode(bytes) do
      {:ok, decoded}
    else
      _ -> invalid()
    end
  end

  defp invalid, do: {:error, %{code: "invalid_token", message: "Invalid bearer token."}}

  defp issuer, do: System.get_env("TREEDB_JWT_ISSUER")
  defp audience, do: System.get_env("TREEDB_JWT_AUDIENCE")
  defp secret, do: System.get_env("TREEDB_JWT_HS256_SECRET")

  defp clock_skew do
    case Integer.parse(System.get_env("TREEDB_JWT_CLOCK_SKEW_SECONDS") || "") do
      {value, _} when value >= 0 -> value
      _ -> @default_skew
    end
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false
end
