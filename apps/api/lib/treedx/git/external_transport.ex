defmodule TreeDx.Git.ExternalTransport do
  @moduledoc false

  alias TreeDx.Git.RemoteUrl

  @timeout_ms 30_000

  def fetch(input, credential) do
    with :ok <- enabled?(),
         :ok <- validate_fetch_transport(input.remoteUrl, credential),
         :ok <- validate_fetch_refspecs(input.refspecs || []) do
      if input.planOnly do
        planned_result(input)
      else
        :ok = recover_stale_destination_locks(input)

        with_credential_environment(credential, fn env ->
          with {:ok, _output} <- run_git(input.repoPath, fetch_args(input), env) do
            {:ok, result(input, "synced", [], nil, nil)}
          end
        end)
      end
    end
  end

  def push(input, credential) do
    with :ok <- enabled?(),
         :ok <- validate_transport(input.remoteUrl, credential),
         {:ok, {source, destination}} <- one_push_refspec(input.refspecs || []),
         :ok <- require_expected_head(input.expectedRemoteHead) do
      if input.planOnly do
        planned_result(input)
      else
        guarded_push(input, credential, source, destination)
      end
    end
  end

  def required?(remote_url, credential_id \\ nil) do
    _credential_id = credential_id
    RemoteUrl.ssh?(remote_url) or RemoteUrl.http?(remote_url)
  end

  defp validate_fetch_transport(remote_url, credential) do
    with :ok <- require_https(remote_url),
         :ok <- require_allowed_host(remote_url),
         :ok <- allow_anonymous_fetch_credential(credential) do
      :ok
    end
  end

  defp guarded_push(input, credential, source, destination) do
    with_credential_environment(credential, fn env ->
      expected = normalize_expected(input.expectedRemoteHead)

      with {:ok, before_head} <- remote_head(input.repoPath, input.remoteUrl, destination, env),
           :ok <- require_remote_match(before_head, expected),
           {:ok, reviewed_commit} <- local_head(input.repoPath, source, env),
           {:ok, _output} <-
             run_git(
               input.repoPath,
               [
                 "push",
                 "--force-with-lease=#{destination}:#{expected || ""}",
                 input.remoteUrl,
                 "#{source}:#{destination}"
               ],
               env
             ),
           {:ok, after_head} <- remote_head(input.repoPath, input.remoteUrl, destination, env),
           :ok <- require_remote_match(after_head, reviewed_commit) do
        {:ok, result(input, "pushed", [destination], before_head, after_head)}
      end
    end)
  end

  defp enabled? do
    if System.get_env("TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED") == "true",
      do: :ok,
      else:
        {:error, %{code: "unsupported_transport", message: "External Git transport is disabled."}}
  end

  defp validate_transport(remote_url, credential) do
    with :ok <- require_https(remote_url),
         :ok <- require_allowed_host(remote_url),
         :ok <- require_token_credential(credential) do
      :ok
    end
  end

  defp require_https(remote_url) do
    if RemoteUrl.http?(remote_url) and String.starts_with?(remote_url, "https://") do
      :ok
    else
      {:error,
       %{
         code: "unsupported_transport",
         message: "External Git transport requires HTTPS; SSH and plaintext HTTP are disabled."
       }}
    end
  end

  defp require_allowed_host(remote_url) do
    host = URI.parse(remote_url).host

    allowed =
      (System.get_env("TREEDX_GIT_ALLOWED_HOSTS") || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.downcase(String.trim(&1)))

    if is_binary(host) and String.downcase(host) in allowed,
      do: :ok,
      else: {:error, %{code: "permission_denied", message: "Remote Git host is not allowlisted."}}
  end

  defp require_token_credential(%{"token" => token}) when is_binary(token) and token != "",
    do: :ok

  defp require_token_credential(%{"password" => token}) when is_binary(token) and token != "",
    do: :ok

  defp require_token_credential(_credential),
    do:
      {:error,
       %{code: "credential_not_configured", message: "A transient HTTPS credential is required."}}

  defp allow_anonymous_fetch_credential(nil), do: :ok
  defp allow_anonymous_fetch_credential(credential), do: require_token_credential(credential)

  defp validate_fetch_refspecs(refspecs) when is_list(refspecs) and refspecs != [] do
    if Enum.all?(refspecs, &safe_fetch_refspec?/1),
      do: :ok,
      else: {:error, %{code: "validation_error", message: "Fetch refspec is unsafe."}}
  end

  defp validate_fetch_refspecs(_),
    do: {:error, %{code: "validation_error", message: "Fetch refspecs are required."}}

  defp safe_fetch_refspec?(refspec) when is_binary(refspec) do
    stripped = String.trim_leading(refspec, "+")

    not String.contains?(stripped, ["*", "\n", "\r", "\0"]) and
      case String.split(stripped, ":", parts: 2) do
        [source, destination] ->
          source != "" and destination != "" and
            safe_fetch_ref?(source) and safe_fetch_ref?(destination)

        _ ->
          false
      end
  end

  defp safe_fetch_refspec?(_), do: false

  defp safe_fetch_ref?(ref) do
    Regex.match?(~r/^refs\/(?:heads|remotes)\/[A-Za-z0-9][A-Za-z0-9._\/-]*$/, ref) and
      not String.contains?(ref, ["..", "//", "@{", "/."]) and
      not String.ends_with?(ref, [".lock", ".", "/"])
  end

  defp recover_stale_destination_locks(input) do
    stale_before = System.system_time(:second) - 60

    Enum.each(input.refspecs || [], fn refspec ->
      [_source, destination] = String.split(String.trim_leading(refspec, "+"), ":", parts: 2)

      git_dir =
        if File.dir?(Path.join(input.repoPath, ".git")),
          do: Path.join(input.repoPath, ".git"),
          else: input.repoPath

      lock_path = Path.join(git_dir, "#{destination}.lock")

      case File.stat(lock_path, time: :posix) do
        {:ok, stat}
        when is_integer(stat.mtime) and stat.mtime <= stale_before ->
          File.rm!(lock_path)

        _ ->
          :ok
      end
    end)

    :ok
  end

  defp one_push_refspec([refspec]) when is_binary(refspec) do
    stripped = String.trim_leading(refspec, "+")

    cond do
      String.contains?(stripped, ["*", "\n", "\r", "\0"]) ->
        {:error,
         %{
           code: "validation_error",
           message: "Wildcard or malformed push refspec is not supported."
         }}

      true ->
        case String.split(stripped, ":", parts: 2) do
          [source, destination]
          when source != "" and destination != "" and
                 is_binary(source) and is_binary(destination) ->
            {:ok, {source, destination}}

          _ ->
            {:error,
             %{code: "validation_error", message: "A non-deleting push refspec is required."}}
        end
    end
  end

  defp one_push_refspec(_),
    do: {:error, %{code: "validation_error", message: "Exactly one push refspec is required."}}

  defp require_expected_head(value) when is_binary(value), do: :ok

  defp require_expected_head(_),
    do:
      {:error,
       %{code: "validation_error", message: "expectedRemoteHead is required for external push."}}

  defp normalize_expected(""), do: nil
  defp normalize_expected(value), do: value

  defp require_remote_match(actual, expected) when actual == expected, do: :ok

  defp require_remote_match(actual, expected) do
    {:error,
     %{
       code: "remote_head_conflict",
       message: "Remote head changed before the guarded Git operation.",
       expectedRemoteHead: expected,
       actualRemoteHead: actual
     }}
  end

  defp remote_head(repo_path, remote_url, destination, env) do
    with {:ok, output} <-
           run_git(repo_path, ["ls-remote", "--refs", remote_url, destination], env) do
      case String.split(String.trim(output), ~r/\s+/, parts: 2) do
        [""] -> {:ok, nil}
        [head, ^destination] when byte_size(head) in [40, 64] -> {:ok, head}
        _ -> {:error, %{code: "git_error", message: "Remote head response was invalid."}}
      end
    end
  end

  defp local_head(repo_path, source, env) do
    with {:ok, output} <- run_git(repo_path, ["rev-parse", "--verify", "#{source}^{commit}"], env) do
      head = String.trim(output)

      if byte_size(head) in [40, 64],
        do: {:ok, head},
        else: {:error, %{code: "git_error", message: "Reviewed source commit was invalid."}}
    end
  end

  defp fetch_args(input), do: ["fetch", "--no-tags", input.remoteUrl | input.refspecs || []]

  defp planned_result(input) do
    {:ok, result(input, "plan", input.refspecs || [], Map.get(input, :expectedRemoteHead), nil)}
  end

  defp result(input, status, updated_refs, before_head, after_head) do
    %{
      "remoteName" => input.remoteName || "origin",
      "remoteUrl" => RemoteUrl.sanitize(input.remoteUrl),
      "refspecs" => input.refspecs || [],
      "updatedRefs" => updated_refs,
      "rejectedRefs" => [],
      "beforeHead" => before_head,
      "afterHead" => after_head,
      "status" => status,
      "backend" => "git_external_transport"
    }
  end

  defp run_git(repo_path, args, env) do
    task =
      Task.async(fn ->
        System.cmd("git", args, cd: repo_path, env: env, stderr_to_stdout: true)
      end)

    case Task.yield(task, @timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {output, 0}} ->
        {:ok, output}

      {:ok, {_output, _status}} ->
        {:error, %{code: "git_error", message: "Git external transport failed."}}

      _ ->
        {:error, %{code: "git_timeout", message: "Git external transport timed out."}}
    end
  rescue
    ErlangError ->
      {:error, %{code: "unsupported_transport", message: "git executable is not available."}}
  end

  defp with_credential_environment(credential, operation) do
    credential = credential || %{}

    directory =
      Path.join(
        System.tmp_dir!(),
        "treedx-git-askpass-#{System.unique_integer([:positive, :monotonic])}"
      )

    try do
      File.mkdir!(directory)
      script = Path.join(directory, "askpass")

      File.write!(
        script,
        "#!/usr/bin/env sh\ncase \"$1\" in *sername*) printf '%s\\n' \"$TREEDX_GIT_USERNAME\";; *) printf '%s\\n' \"$TREEDX_GIT_SECRET\";; esac\n"
      )

      File.chmod!(script, 0o700)

      env = [
        {"GIT_TERMINAL_PROMPT", "0"},
        {"GIT_CONFIG_NOSYSTEM", "1"},
        {"GIT_CONFIG_GLOBAL", "/dev/null"},
        {"GIT_ASKPASS", script},
        {"TREEDX_GIT_USERNAME", credential["username"] || "x-access-token"},
        {"TREEDX_GIT_SECRET", credential["token"] || credential["password"]}
      ]

      operation.(env)
    after
      File.rm_rf(directory)
    end
  end
end
