defmodule TreeDx.ConfigValidation do
  @moduledoc false

  alias TreeDx.Observability.Scrubber

  @secret_key_fallback String.duplicate("c", 64)

  def validate_boot! do
    case validate_env(System.get_env()) do
      :ok ->
        :ok

      {:error, errors} ->
        message =
          errors
          |> Enum.map(fn error -> "#{error.key}: #{error.message}" end)
          |> Enum.join("; ")

        raise "Invalid TreeDX production configuration: #{message}"
    end
  end

  def validate_release_gate_env(env \\ System.get_env()), do: validate_env(env)

  def validate_env(env) when is_map(env) do
    env = TreeDx.Env.normalize(env)

    errors =
      []
      |> require_secret_key(env)
      |> reject_dev_auth(env)
      |> validate_connected_auth(env)
      |> validate_exec_backend(env)
      |> validate_git_transport(env)
      |> validate_restore(env)
      |> validate_data_dir(env)
      |> validate_logger(env)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp production?(env), do: env["MIX_ENV"] == "prod" or env["TREEDX_ENV"] == "prod"

  defp require_secret_key(errors, env) do
    if production?(env) and blank?(env["SECRET_KEY_BASE"]) do
      add(errors, "missing_secret_key_base", "SECRET_KEY_BASE is required.", "SECRET_KEY_BASE")
    else
      reject_fallback_secret(errors, env)
    end
  end

  defp reject_fallback_secret(errors, env) do
    if production?(env) and env["SECRET_KEY_BASE"] == @secret_key_fallback do
      add(
        errors,
        "fallback_secret_key_base",
        "SECRET_KEY_BASE uses an insecure fallback.",
        "SECRET_KEY_BASE"
      )
    else
      errors
    end
  end

  defp reject_dev_auth(errors, env) do
    auth_mode = env["TREEDX_AUTH_MODE"] || "dev"

    if production?(env) and auth_mode == "dev" do
      add(
        errors,
        "dev_auth_in_production",
        "dev auth mode is not allowed in production.",
        "TREEDX_AUTH_MODE"
      )
    else
      errors
    end
  end

  defp validate_connected_auth(errors, env) do
    if production?(env) and env["TREEDX_AUTH_MODE"] == "connected" do
      verifier = env["TREEDX_AUTH_VERIFIER"]

      errors =
        if blank?(verifier) do
          add(
            errors,
            "missing_auth_verifier",
            "connected auth requires a verifier.",
            "TREEDX_AUTH_VERIFIER"
          )
        else
          errors
        end

      errors =
        if verifier == "hs256_dev" and env["TREEDX_ALLOW_DEV_VERIFIER_IN_PROD"] != "true" do
          add(
            errors,
            "dev_verifier_in_production",
            "hs256_dev verifier is disabled in production.",
            "TREEDX_AUTH_VERIFIER"
          )
        else
          errors
        end

      case verifier do
        "hs256_dev" ->
          require_keys(errors, env, [
            {"TREEDX_JWT_ISSUER", "missing_jwt_issuer"},
            {"TREEDX_JWT_AUDIENCE", "missing_jwt_audience"},
            {"TREEDX_JWT_HS256_SECRET", "missing_hs256_secret"}
          ])

        "jwks_oidc" ->
          require_keys(errors, env, [
            {"TREEDX_JWT_ISSUER", "missing_jwt_issuer"},
            {"TREEDX_JWT_AUDIENCE", "missing_jwt_audience"},
            {"TREEDX_JWKS_URL", "missing_jwks_url"},
            {"TREEDX_JWT_ALLOWED_ALGS", "missing_allowed_algs"}
          ])

        "trusted_internal" ->
          add(
            errors,
            "trusted_internal_verifier",
            "trusted_internal verifier is not allowed for production boot.",
            "TREEDX_AUTH_VERIFIER"
          )

        _ ->
          errors
      end
    else
      errors
    end
  end

  defp validate_exec_backend(errors, env) do
    backend = env["TREEDX_EXEC_BACKEND"] || "direct_dev"

    errors =
      if production?(env) and backend == "direct_dev" and
           env["TREEDX_ALLOW_DIRECT_EXEC_IN_PROD"] != "true" do
        add(
          errors,
          "direct_exec_in_production",
          "direct_dev exec backend is disabled in production.",
          "TREEDX_EXEC_BACKEND"
        )
      else
        errors
      end

    if production?(env) and backend in ["external_worker", "firecracker_or_microvm"] do
      errors
      |> require_keys(env, [{"TREEDX_EXEC_WORKER_URL", "missing_exec_worker_url"}])
      |> require_one(
        env,
        ["TREEDX_EXEC_WORKER_TOKEN", "TREEDX_EXEC_WORKER_HMAC_SECRET"],
        "missing_exec_worker_secret"
      )
    else
      errors
    end
  end

  defp validate_git_transport(errors, env) do
    provider = env["TREEDX_REMOTE_CREDENTIAL_PROVIDER"] || "none"

    errors =
      if truthy?(env["TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED"]) and provider == "none" do
        add(
          errors,
          "missing_remote_credential_provider",
          "external Git transport requires a credential provider.",
          "TREEDX_REMOTE_CREDENTIAL_PROVIDER"
        )
      else
        errors
      end

    errors =
      if provider == "treeseed_bridge" do
        errors
        |> require_keys(env, [
          {"TREEDX_TREESEED_TEAM_ID", "missing_treeseed_team_id"},
          {"TREEDX_TREESEED_PROJECT_ID", "missing_treeseed_project_id"},
          {"TREEDX_TREESEED_REPOSITORY", "missing_treeseed_repository"},
          {"TREEDX_TREESEED_GITHUB_INSTALLATION_ID", "missing_treeseed_github_installation_id"}
        ])
        |> require_one(
          env,
          ["TREEDX_TREESEED_API_BASE_URL", "TREESEED_API_BASE_URL"],
          "missing_treeseed_api_base_url"
        )
        |> require_one(
          env,
          ["TREEDX_TREESEED_SERVICE_ID", "TREESEED_WEB_SERVICE_ID"],
          "missing_treeseed_service_id"
        )
        |> require_one(
          env,
          ["TREEDX_TREESEED_SERVICE_SECRET", "TREESEED_WEB_SERVICE_SECRET"],
          "missing_treeseed_service_secret"
        )
      else
        errors
      end

    if truthy?(env["TREEDX_GIT_SSH_ENABLED"]) do
      errors
      |> require_keys(env, [{"TREEDX_GIT_SSH_KNOWN_HOSTS", "missing_ssh_known_hosts"}])
      |> require_credential_provider(provider)
    else
      errors
    end
  end

  defp validate_restore(errors, env) do
    if truthy?(env["TREEDX_STORAGE_RESTORE_ENABLED"]) and
         env["TREEDX_STORAGE_RESTORE_ACK"] != "true" do
      add(
        errors,
        "restore_ack_required",
        "storage restore requires explicit acknowledgement.",
        "TREEDX_STORAGE_RESTORE_ACK"
      )
    else
      errors
    end
  end

  defp validate_data_dir(errors, env) do
    cond do
      not production?(env) ->
        errors

      blank?(env["TREEDX_DATA_DIR"]) ->
        add(errors, "missing_data_dir", "TREEDX_DATA_DIR is required.", "TREEDX_DATA_DIR")

      Path.type(env["TREEDX_DATA_DIR"]) != :absolute ->
        add(errors, "relative_data_dir", "TREEDX_DATA_DIR must be absolute.", "TREEDX_DATA_DIR")

      not writable_dir?(env["TREEDX_DATA_DIR"]) ->
        add(errors, "unwritable_data_dir", "TREEDX_DATA_DIR must be writable.", "TREEDX_DATA_DIR")

      true ->
        errors
    end
  end

  defp validate_logger(errors, env) do
    if production?(env) do
      case Application.get_env(:logger, :console, [])[:format] do
        {TreeDx.Observability.JsonLogFormatter, :format} ->
          errors

        _ ->
          add(
            errors,
            "json_log_formatter_required",
            "production logs must use the JSON formatter.",
            "logger.console.format"
          )
      end
    else
      errors
    end
  end

  defp require_keys(errors, env, keys) do
    Enum.reduce(keys, errors, fn {key, code}, acc ->
      if blank?(env[key]), do: add(acc, code, "#{key} is required.", key), else: acc
    end)
  end

  defp require_one(errors, env, keys, code) do
    if Enum.any?(keys, &(not blank?(env[&1]))) do
      errors
    else
      add(errors, code, "#{Enum.join(keys, " or ")} is required.", Enum.join(keys, "|"))
    end
  end

  defp require_credential_provider(errors, "none"),
    do:
      add(
        errors,
        "missing_remote_credential_provider",
        "SSH requires a credential provider.",
        "TREEDX_REMOTE_CREDENTIAL_PROVIDER"
      )

  defp require_credential_provider(errors, _provider), do: errors

  defp writable_dir?(path) do
    File.mkdir_p(path)
    probe = Path.join(path, ".treedx-config-write-check-#{System.unique_integer([:positive])}")

    case File.write(probe, "ok") do
      :ok ->
        File.rm(probe)
        true

      _ ->
        false
    end
  rescue
    _ -> false
  end

  defp add(errors, code, message, key) do
    [%{code: code, message: Scrubber.scrub(message), key: key} | errors]
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
end
