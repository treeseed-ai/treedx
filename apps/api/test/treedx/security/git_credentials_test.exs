defmodule TreeDx.GitCredentialsTest do
  use ExUnit.Case, async: false

  setup do
    original =
      for name <- [
            "TREEDX_REMOTE_CREDENTIAL_PROVIDER",
            "TREEDX_REMOTE_CREDENTIAL_BROKER_URL",
            "TREEDX_REMOTE_CREDENTIAL_BROKER_SERVICE_ID",
            "TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION"
          ],
          into: %{},
          do: {name, System.get_env(name)}

    on_exit(fn ->
      Enum.each(original, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "HTTP broker provider fails closed when required configuration is missing" do
    System.put_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER", "http_broker")

    assert {:error, error} = TreeDx.Git.Credentials.resolve("repo-read")
    assert error.code == "credential_not_configured"
  end

  test "HTTP broker resolves one opaque credential delivery" do
    {:ok, port, task} = start_bridge_server()
    System.put_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER", "http_broker")

    System.put_env(
      "TREEDX_REMOTE_CREDENTIAL_BROKER_URL",
      "http://127.0.0.1:#{port}/v1/internal/credential-deliveries/consume"
    )

    System.put_env("TREEDX_REMOTE_CREDENTIAL_BROKER_SERVICE_ID", "node-1")
    System.put_env("TREEDX_REMOTE_CREDENTIAL_BROKER_ASSERTION", "broker-assertion")

    assert {:ok, credential} = TreeDx.Git.Credentials.resolve("repo-write")

    assert credential == %{
             "id" => "repo-write",
             "type" => "token",
             "username" => "x-access-token",
             "token" => "ghs_treedx_transient_token"
           }

    request = Task.await(task, 2_000)
    assert request =~ "POST /v1/internal/credential-deliveries/consume"
    assert request =~ "x-treedx-node-id: node-1"
    assert request =~ ~s("deliveryId":"repo-write")
    refute request =~ "private-key"
  end

  defp start_bridge_server do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listen)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen, 2_000)
        {:ok, request} = recv_http(socket, "")

        [_, request_body] = String.split(request, "\r\n\r\n", parts: 2)
        request_payload = Jason.decode!(request_body)
        body = Jason.encode!(%{ok: true, payload: sealed_payload(request_payload)})

        response = [
          "HTTP/1.1 201 Created\r\n",
          "content-type: application/json\r\n",
          "content-length: #{byte_size(body)}\r\n",
          "connection: close\r\n",
          "\r\n",
          body
        ]

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        :gen_tcp.close(listen)
        request
      end)

    {:ok, port, task}
  end

  defp sealed_payload(request) do
    node_public = Base.decode64!(request["nodePublicKey"])
    {ephemeral_public, ephemeral_private} = :crypto.generate_key(:ecdh, :x25519)
    shared = :crypto.compute_key(:ecdh, node_public, ephemeral_private, :x25519)
    pseudorandom_key = :crypto.mac(:hmac, :sha256, request["deliveryId"], shared)
    key = :crypto.mac(:hmac, :sha256, pseudorandom_key, "treedx-credential-delivery-v1" <> <<1>>)
    nonce = :crypto.strong_rand_bytes(12)

    aad =
      Enum.join(
        [
          request["deliveryId"],
          request["operation"] || "",
          request["allowedHost"] || "",
          request["refspecDigest"] || "",
          "node-1"
        ],
        "\n"
      )

    plaintext =
      Jason.encode!(%{
        type: "token",
        username: "x-access-token",
        token: "ghs_treedx_transient_token",
        expiresAt: "2026-06-17T22:30:00.000Z"
      })

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:chacha20_poly1305, key, nonce, plaintext, aad, true)

    %{
      algorithm: "x25519-hkdf-sha256-chacha20-poly1305/v1",
      ephemeralPublicKey: Base.encode64(ephemeral_public),
      nonce: Base.encode64(nonce),
      ciphertext: Base.encode64(ciphertext),
      tag: Base.encode64(tag)
    }
  end

  defp recv_http(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} ->
        next = acc <> chunk

        if String.contains?(next, "\r\n\r\n") do
          content_length =
            Regex.run(~r/content-length:\s*(\d+)/i, next)
            |> case do
              [_, value] -> String.to_integer(value)
              _ -> 0
            end

          [headers, body] = String.split(next, "\r\n\r\n", parts: 2)

          if byte_size(body) >= content_length do
            {:ok, headers <> "\r\n\r\n" <> body}
          else
            recv_http(socket, next)
          end
        else
          recv_http(socket, next)
        end

      other ->
        other
    end
  end
end
