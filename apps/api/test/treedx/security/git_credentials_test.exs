defmodule TreeDx.GitCredentialsTest do
  use ExUnit.Case, async: false

  setup do
    original =
      for name <- [
            "TREEDX_REMOTE_CREDENTIAL_PROVIDER",
            "TREEDX_TREESEED_API_BASE_URL",
            "TREEDX_TREESEED_TEAM_ID",
            "TREEDX_TREESEED_PROJECT_ID",
            "TREEDX_TREESEED_REPOSITORY",
            "TREEDX_TREESEED_GITHUB_INSTALLATION_ID",
            "TREEDX_TREESEED_CREDENTIAL_OPERATION",
            "TREEDX_TREESEED_SERVICE_ID",
            "TREEDX_TREESEED_SERVICE_SECRET"
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

  test "treeseed bridge provider fails closed when required configuration is missing" do
    System.put_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER", "treeseed_bridge")

    assert {:error, error} = TreeDx.Git.Credentials.resolve("repo-read")
    assert error.code == "credential_not_configured"
  end

  test "treeseed bridge provider resolves a token credential from the configured endpoint" do
    {:ok, port, task} = start_bridge_server()
    System.put_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER", "treeseed_bridge")
    System.put_env("TREEDX_TREESEED_API_BASE_URL", "http://127.0.0.1:#{port}")
    System.put_env("TREEDX_TREESEED_TEAM_ID", "team-1")
    System.put_env("TREEDX_TREESEED_PROJECT_ID", "project-1")
    System.put_env("TREEDX_TREESEED_REPOSITORY", "treeseed-ai/project")
    System.put_env("TREEDX_TREESEED_GITHUB_INSTALLATION_ID", "99")
    System.put_env("TREEDX_TREESEED_CREDENTIAL_OPERATION", "push")
    System.put_env("TREEDX_TREESEED_SERVICE_ID", "treedx")
    System.put_env("TREEDX_TREESEED_SERVICE_SECRET", "bridge-secret")

    assert {:ok, credential} = TreeDx.Git.Credentials.resolve("repo-write")

    assert credential == %{
             "id" => "repo-write",
             "type" => "token",
             "username" => "x-access-token",
             "token" => "ghs_treedx_transient_token"
           }

    request = Task.await(task, 2_000)
    assert request =~ "POST /v1/internal/treedx/credentials/github-app"
    assert request =~ "x-treeseed-service-id: treedx"
    assert request =~ ~s("operation":"push")
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

        body =
          Jason.encode!(%{
            ok: true,
            payload: %{
              id: "repo-write",
              type: "token",
              username: "x-access-token",
              token: "ghs_treedx_transient_token",
              expiresAt: "2026-06-17T22:30:00.000Z",
              provider: "github-app",
              repository: "treeseed-ai/project",
              allowedOperations: ["push"],
              issuanceId: "issuance-1"
            }
          })

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
