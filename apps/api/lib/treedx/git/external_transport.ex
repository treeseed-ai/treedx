defmodule TreeDx.Git.ExternalTransport do
  @moduledoc false

  alias TreeDx.Git.RemoteUrl

  def fetch(input, credential) do
    with :ok <- enabled?(),
         :ok <- validate_transport(input.remoteUrl, credential) do
      run_git(input.repoPath, fetch_args(input), input, credential, "synced")
    end
  end

  def push(input, credential) do
    with :ok <- enabled?(),
         :ok <- validate_transport(input.remoteUrl, credential) do
      run_git(
        input.repoPath,
        push_args(input),
        input,
        credential,
        if(input.dryRun, do: "dry_run", else: "pushed")
      )
    end
  end

  def required?(remote_url, credential_id \\ nil) do
    RemoteUrl.ssh?(remote_url) or
      (RemoteUrl.http?(remote_url) and is_binary(credential_id) and credential_id != "")
  end

  defp enabled? do
    if System.get_env("TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED") == "true" do
      :ok
    else
      {:error, %{code: "unsupported_transport", message: "External Git transport is disabled."}}
    end
  end

  defp validate_transport(remote_url, credential) do
    cond do
      RemoteUrl.ssh?(remote_url) ->
        cond do
          System.get_env("TREEDX_GIT_SSH_ENABLED") != "true" ->
            {:error, %{code: "unsupported_transport", message: "SSH Git transport is disabled."}}

          not is_map(credential) or not is_binary(credential["keyPath"]) ->
            {:error,
             %{code: "credential_not_configured", message: "SSH credential is not configured."}}

          not is_binary(System.get_env("TREEDX_GIT_SSH_KNOWN_HOSTS")) ->
            {:error,
             %{
               code: "validation_error",
               message: "TREEDX_GIT_SSH_KNOWN_HOSTS is required for SSH."
             }}

          true ->
            :ok
        end

      RemoteUrl.http?(remote_url) ->
        if is_map(credential) do
          :ok
        else
          {:error,
           %{
             code: "credential_not_configured",
             message: "credentialId is required for authenticated Git transport."
           }}
        end

      true ->
        :ok
    end
  end

  defp fetch_args(input) do
    remote = input.remoteUrl
    refspecs = input.refspecs || []
    ["fetch", "--prune", remote | refspecs]
  end

  defp push_args(input) do
    args = ["push"]
    args = if input.dryRun, do: args ++ ["--dry-run"], else: args
    args ++ [input.remoteUrl | input.refspecs || []]
  end

  defp run_git(repo_path, args, input, credential, status) do
    env = credential_env(input.remoteUrl, credential)

    case System.cmd("git", args,
           cd: repo_path,
           env: env,
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        {:ok,
         %{
           "remoteName" => input.remoteName || "origin",
           "remoteUrl" => RemoteUrl.sanitize(input.remoteUrl),
           "refspecs" => input.refspecs || [],
           "updatedRefs" => [],
           "rejectedRefs" => [],
           "beforeHead" => nil,
           "afterHead" => nil,
           "status" => status,
           "backend" => "git_external_transport"
         }}

      {_output, _status} ->
        {:error, %{code: "git_error", message: "Git external transport failed."}}
    end
  rescue
    ErlangError ->
      {:error, %{code: "unsupported_transport", message: "git executable is not available."}}
  end

  defp credential_env(remote_url, credential) do
    base = [
      {"GIT_TERMINAL_PROMPT", "0"},
      {"GIT_CONFIG_NOSYSTEM", "1"}
    ]

    cond do
      RemoteUrl.ssh?(remote_url) ->
        known_hosts = System.get_env("TREEDX_GIT_SSH_KNOWN_HOSTS")
        key_path = credential["keyPath"]

        base ++
          [
            {"GIT_SSH_COMMAND",
             "ssh -i #{shell_escape(key_path)} -o UserKnownHostsFile=#{shell_escape(known_hosts)} -o StrictHostKeyChecking=yes"}
          ]

      is_binary(credential["token"]) ->
        base ++ [{"GIT_ASKPASS", askpass_script()}, {"TREEDX_GIT_SECRET", credential["token"]}]

      is_binary(credential["password"]) ->
        base ++ [{"GIT_ASKPASS", askpass_script()}, {"TREEDX_GIT_SECRET", credential["password"]}]

      true ->
        base
    end
  end

  defp askpass_script do
    path =
      Path.join(System.tmp_dir!(), "treedx-git-askpass-#{System.unique_integer([:positive])}.sh")

    File.write!(path, "#!/usr/bin/env sh\nprintf '%s\\n' \"$TREEDX_GIT_SECRET\"\n")
    File.chmod!(path, 0o700)
    path
  end

  defp shell_escape(value) do
    value
    |> to_string()
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end
end
