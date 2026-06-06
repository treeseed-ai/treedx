defmodule TreeDx.Auth.Connected do
  @moduledoc false

  alias TreeDx.Auth.{Principal, Verifier}

  def authenticate(token) do
    case Verifier.verify(token) do
      {:ok, claims} ->
        with {:ok, principal} <- Principal.from_claims(claims) do
          persist_seen_token(claims, principal)

          TreeDx.Audit.append("auth.verified", %{
            actor_id: principal.actorId,
            tenant_id: principal.tenantId,
            status: "ok"
          })

          {:ok, principal}
        end

      {:error, error} ->
        TreeDx.Audit.append("auth.rejected", %{
          status: "error",
          data: %{code: error[:code] || error["code"]}
        })

        {:error, error}
    end
  end

  def validate_config, do: Verifier.validate_config()

  def verifier_info, do: Verifier.info()

  defp persist_seen_token(%{"jti" => jti} = claims, principal)
       when is_binary(jti) and jti != "" do
    expires_at = DateTime.from_unix!(trunc(claims["exp"]))

    TreeDx.Store.put_connected_token(%{
      jti: jti,
      actorId: principal.actorId,
      tenantId: principal.tenantId,
      issuer: claims["iss"],
      audience: audience_string(claims["aud"]),
      subject: claims["sub"] || principal.actorId,
      expiresAt: DateTime.to_iso8601(expires_at),
      seenAt: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp persist_seen_token(_claims, _principal), do: :ok

  defp audience_string(value) when is_list(value), do: Enum.join(value, ",")
  defp audience_string(value) when is_binary(value), do: value
  defp audience_string(_), do: ""
end
