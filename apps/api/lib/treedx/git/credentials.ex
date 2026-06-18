defmodule TreeDx.Git.Credentials do
  @moduledoc false

  def resolve(nil), do: {:ok, nil}
  def resolve(""), do: {:ok, nil}

  def resolve(credential_id) when is_binary(credential_id) do
    case provider() do
      "none" ->
        {:error,
         %{code: "credential_not_configured", message: "Git credential provider is disabled."}}

      "env_file" ->
        resolve_env_file(credential_id)

      "external_command" ->
        resolve_external_command(credential_id)

      "treeseed_bridge" ->
        resolve_treeseed_bridge(credential_id)

      other ->
        {:error, %{code: "validation_error", message: "Unknown credential provider #{other}."}}
    end
  end

  def resolve(_credential_id),
    do: {:error, %{code: "validation_error", message: "credentialId must be a string."}}

  defp provider, do: System.get_env("TREEDX_REMOTE_CREDENTIAL_PROVIDER") || "none"

  defp resolve_env_file(credential_id) do
    with path when is_binary(path) and path != "" <-
           System.get_env("TREEDX_REMOTE_CREDENTIALS_FILE"),
         {:ok, body} <- File.read(path),
         {:ok, parsed} <- Jason.decode(body),
         %{} = credential <- Map.get(parsed, credential_id) do
      {:ok, sanitize_shape(Map.put(credential, "id", credential_id))}
    else
      nil ->
        {:error, %{code: "credential_not_configured", message: "credentialId was not found."}}

      "" ->
        {:error,
         %{
           code: "credential_not_configured",
           message: "TREEDX_REMOTE_CREDENTIALS_FILE is not configured."
         }}

      {:error, _reason} ->
        {:error, %{code: "credential_not_configured", message: "Unable to read credential file."}}

      _ ->
        {:error, %{code: "credential_not_configured", message: "credentialId was not found."}}
    end
  end

  defp resolve_external_command(credential_id) do
    with command when is_binary(command) and command != "" <-
           System.get_env("TREEDX_REMOTE_CREDENTIAL_COMMAND"),
         {body, 0} <- System.cmd(command, [credential_id], stderr_to_stdout: false),
         {:ok, credential} <- Jason.decode(body) do
      {:ok, sanitize_shape(Map.put(credential, "id", credential_id))}
    else
      _ ->
        {:error, %{code: "credential_not_configured", message: "Credential command failed."}}
    end
  end

  defp resolve_treeseed_bridge(credential_id) do
    with {:ok, endpoint} <- treeseed_bridge_endpoint(),
         {:ok, body} <- treeseed_bridge_body(credential_id),
         {:ok, response} <- post_treeseed_bridge(endpoint, body),
         %{} = credential <- response["payload"] do
      {:ok, sanitize_shape(Map.put(credential, "id", credential_id))}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error,
         %{code: "credential_not_configured", message: "TreeSeed credential bridge failed."}}
    end
  end

  defp treeseed_bridge_endpoint do
    base =
      System.get_env("TREEDX_TREESEED_API_BASE_URL") || System.get_env("TREESEED_API_BASE_URL")

    if is_binary(base) and String.trim(base) != "" do
      endpoint =
        base
        |> String.trim()
        |> String.trim_trailing("/")
        |> Kernel.<>("/v1/internal/treedx/credentials/github-app")

      {:ok, endpoint}
    else
      {:error,
       %{
         code: "credential_not_configured",
         message: "TREEDX_TREESEED_API_BASE_URL is required for TreeSeed credential bridge."
       }}
    end
  end

  defp treeseed_bridge_body(credential_id) do
    with {:ok, team_id} <- required_env("TREEDX_TREESEED_TEAM_ID"),
         {:ok, project_id} <- required_env("TREEDX_TREESEED_PROJECT_ID"),
         {:ok, repository} <- required_env("TREEDX_TREESEED_REPOSITORY"),
         {:ok, installation_id} <- required_env("TREEDX_TREESEED_GITHUB_INSTALLATION_ID") do
      operation = System.get_env("TREEDX_TREESEED_CREDENTIAL_OPERATION") || "fetch"

      body =
        %{
          teamId: team_id,
          projectId: project_id,
          repository: repository,
          installationId: installation_id,
          operation: operation,
          credentialId: credential_id,
          ref: env_optional("TREEDX_TREESEED_REF"),
          assignmentId: env_optional("TREEDX_TREESEED_ASSIGNMENT_ID"),
          providerId: env_optional("TREEDX_TREESEED_PROVIDER_ID"),
          workdayId: env_optional("TREEDX_TREESEED_WORKDAY_ID"),
          paths: env_csv("TREEDX_TREESEED_PATHS"),
          actor: %{
            type: "treedx",
            serviceId:
              System.get_env("TREEDX_TREESEED_SERVICE_ID") ||
                System.get_env("TREESEED_WEB_SERVICE_ID")
          }
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) or value == [] end)
        |> Map.new()

      {:ok, Jason.encode!(body)}
    end
  end

  defp post_treeseed_bridge(endpoint, body) do
    with {:ok, service_id} <-
           service_env("TREEDX_TREESEED_SERVICE_ID", "TREESEED_WEB_SERVICE_ID"),
         {:ok, service_secret} <-
           service_env("TREEDX_TREESEED_SERVICE_SECRET", "TREESEED_WEB_SERVICE_SECRET") do
      :inets.start()
      :ssl.start()

      headers = [
        {~c"content-type", ~c"application/json"},
        {~c"x-treeseed-service-id", String.to_charlist(service_id)},
        {~c"x-treeseed-service-secret", String.to_charlist(service_secret)}
      ]

      request = {String.to_charlist(endpoint), headers, ~c"application/json", body}

      case :httpc.request(:post, request, [timeout: 10_000], body_format: :binary) do
        {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
          Jason.decode(response_body)

        {:ok, {{_, status, _}, _headers, _response_body}} ->
          {:error,
           %{
             code: "credential_not_configured",
             message: "TreeSeed credential bridge returned HTTP #{status}."
           }}

        {:error, _reason} ->
          {:error,
           %{
             code: "credential_not_configured",
             message: "TreeSeed credential bridge unavailable."
           }}
      end
    end
  end

  defp required_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, %{code: "credential_not_configured", message: "#{name} is required."}}
    end
  end

  defp service_env(primary, fallback) do
    case System.get_env(primary) || System.get_env(fallback) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, %{code: "credential_not_configured", message: "#{primary} is required."}}
    end
  end

  defp env_optional(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp env_csv(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp sanitize_shape(credential) do
    credential
    |> Map.take(["id", "type", "username", "password", "token", "keyPath"])
    |> Map.put_new("type", "token")
  end
end
