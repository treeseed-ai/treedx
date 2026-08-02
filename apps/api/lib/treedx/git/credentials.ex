defmodule TreeDx.Git.Credentials do
  @moduledoc false

  def resolve(delivery_id, context \\ %{})
  def resolve(nil, _context), do: {:ok, nil}
  def resolve("", _context), do: {:ok, nil}

  def resolve(delivery_id, context) when is_binary(delivery_id) do
    case provider() do
      "none" ->
        {:error,
         %{code: "credential_not_configured", message: "Git credential provider is disabled."}}

      "env_file" ->
        resolve_env_file(delivery_id)

      "external_command" ->
        resolve_external_command(delivery_id)

      "http_broker" ->
        resolve_http_broker(delivery_id, context)

      other ->
        {:error, %{code: "validation_error", message: "Unknown credential provider #{other}."}}
    end
  end

  def resolve(_delivery_id, _context),
    do:
      {:error,
       %{code: "validation_error", message: "credentialId must be an opaque delivery identifier."}}

  defp provider, do: System.get_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER") || "none"

  defp resolve_env_file(delivery_id) do
    with path when is_binary(path) and path != "" <-
           System.get_env("TREEDX_REMOTE_CREDENTIALS_FILE"),
         {:ok, body} <- File.read(path),
         {:ok, parsed} <- Jason.decode(body),
         %{} = credential <- Map.get(parsed, delivery_id) do
      {:ok, sanitize_shape(Map.put(credential, "id", delivery_id))}
    else
      "" ->
        {:error,
         %{
           code: "credential_not_configured",
           message: "TREEDX_REMOTE_CREDENTIALS_FILE is not configured."
         }}

      _ ->
        {:error, %{code: "credential_not_configured", message: "credentialId was not found."}}
    end
  end

  defp resolve_external_command(delivery_id) do
    with command when is_binary(command) and command != "" <-
           System.get_env("TREEDX_REMOTE_CREDENTIAL_COMMAND"),
         {body, 0} <- System.cmd(command, [delivery_id], stderr_to_stdout: false),
         {:ok, credential} <- Jason.decode(body) do
      {:ok, sanitize_shape(Map.put(credential, "id", delivery_id))}
    else
      _ -> {:error, %{code: "credential_not_configured", message: "Credential command failed."}}
    end
  end

  defp resolve_http_broker(delivery_id, context) do
    {node_public_key, node_private_key} = :crypto.generate_key(:ecdh, :x25519)

    with {:ok, endpoint} <- required_env("TREEDX_REMOTE_CREDENTIAL_BROKER_URL"),
         {:ok, service_id} <- required_env("TREEDX_REMOTE_CREDENTIAL_BROKER_SERVICE_ID"),
         {:ok, service_assertion} <- required_env("TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION"),
         {:ok, response} <-
           post_broker(
             endpoint,
             service_id,
             service_assertion,
             delivery_id,
             Base.encode64(node_public_key),
             context
           ),
         %{} = envelope <- response["payload"],
         {:ok, credential} <-
           decrypt_delivery(envelope, node_private_key, delivery_id, service_id, context) do
      {:ok, sanitize_shape(Map.put(credential, "id", delivery_id))}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error,
         %{
           code: "credential_not_configured",
           message: "Credential broker returned an invalid delivery."
         }}
    end
  end

  defp post_broker(endpoint, service_id, assertion, delivery_id, node_public_key, context) do
    :inets.start()
    :ssl.start()

    body =
      Jason.encode!(%{
        deliveryId: delivery_id,
        nodePublicKey: node_public_key,
        operation: context[:operation],
        allowedHost: context[:allowedHost],
        refspecDigest: context[:refspecDigest]
      })

    headers = [
      {~c"content-type", ~c"application/json"},
      {~c"x-treedx-node-id", String.to_charlist(service_id)},
      {~c"authorization", String.to_charlist("Bearer #{assertion}")}
    ]

    request = {String.to_charlist(endpoint), headers, ~c"application/json", body}

    case :httpc.request(:post, request, [timeout: 10_000], body_format: :binary) do
      {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
        Jason.decode(response_body)

      {:ok, {{_, status, _}, _headers, _response_body}} ->
        {:error,
         %{
           code: "credential_not_configured",
           message: "Credential broker returned HTTP #{status}."
         }}

      {:error, _reason} ->
        {:error,
         %{code: "credential_not_configured", message: "Credential broker is unavailable."}}
    end
  end

  defp decrypt_delivery(envelope, private_key, delivery_id, service_id, context) do
    with "x25519-hkdf-sha256-chacha20-poly1305/v1" <- envelope["algorithm"],
         {:ok, ephemeral_public} <- Base.decode64(envelope["ephemeralPublicKey"] || ""),
         true <- byte_size(ephemeral_public) == 32,
         {:ok, nonce} <- Base.decode64(envelope["nonce"] || ""),
         true <- byte_size(nonce) == 12,
         {:ok, ciphertext} <- Base.decode64(envelope["ciphertext"] || ""),
         {:ok, tag} <- Base.decode64(envelope["tag"] || ""),
         true <- byte_size(tag) == 16,
         shared <- :crypto.compute_key(:ecdh, ephemeral_public, private_key, :x25519),
         key <- hkdf_sha256(shared, delivery_id, "treedx-credential-delivery-v1"),
         aad <-
           Enum.join(
             [
               delivery_id,
               context[:operation] || "",
               context[:allowedHost] || "",
               context[:refspecDigest] || "",
               service_id
             ],
             "\n"
           ),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :chacha20_poly1305,
             key,
             nonce,
             ciphertext,
             aad,
             tag,
             false
           ),
         {:ok, credential} <- Jason.decode(plaintext),
         true <- is_map(credential) do
      {:ok, credential}
    else
      _ ->
        {:error,
         %{
           code: "credential_not_configured",
           message: "Credential delivery decryption failed."
         }}
    end
  end

  defp hkdf_sha256(input_key_material, salt, info) do
    pseudorandom_key = :crypto.mac(:hmac, :sha256, salt, input_key_material)
    :crypto.mac(:hmac, :sha256, pseudorandom_key, info <> <<1>>)
  end

  defp required_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, %{code: "credential_not_configured", message: "#{name} is required."}}
    end
  end

  defp sanitize_shape(credential) do
    credential
    |> Map.take(["id", "type", "username", "password", "token"])
    |> Map.put_new("type", "token")
  end
end
