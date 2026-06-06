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

  defp sanitize_shape(credential) do
    credential
    |> Map.take(["id", "type", "username", "password", "token", "keyPath"])
    |> Map.put_new("type", "token")
  end
end
