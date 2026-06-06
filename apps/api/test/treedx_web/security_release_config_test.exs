defmodule TreeDxWeb.SecurityReleaseConfigTest do
  use ExUnit.Case, async: false

  alias TreeDx.ConfigValidation

  setup do
    previous_logger = Application.get_env(:logger, :console)

    Application.put_env(:logger, :console,
      format: {TreeDx.Observability.JsonLogFormatter, :format},
      metadata: :all
    )

    dir =
      Path.join(
        System.tmp_dir!(),
        "treedx-config-validation-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    on_exit(fn ->
      Application.put_env(:logger, :console, previous_logger || [])
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "accepts hardened production configuration", %{dir: dir} do
    assert :ok = ConfigValidation.validate_env(base_env(dir))
  end

  test "rejects insecure production auth and verifier settings", %{dir: dir} do
    assert_codes(Map.merge(base_env(dir), %{"TREEDX_AUTH_MODE" => "dev"}), [
      "dev_auth_in_production"
    ])

    assert_codes(
      base_env(dir)
      |> Map.delete("TREEDX_AUTH_VERIFIER"),
      ["missing_auth_verifier"]
    )

    assert_codes(
      Map.merge(base_env(dir), %{
        "TREEDX_AUTH_VERIFIER" => "hs256_dev",
        "TREEDX_JWT_ISSUER" => "",
        "TREEDX_JWT_AUDIENCE" => "",
        "TREEDX_JWT_HS256_SECRET" => ""
      }),
      [
        "dev_verifier_in_production",
        "missing_jwt_issuer",
        "missing_jwt_audience",
        "missing_hs256_secret"
      ]
    )
  end

  test "rejects insecure production execution and transport settings", %{dir: dir} do
    assert_codes(Map.merge(base_env(dir), %{"TREEDX_EXEC_BACKEND" => "direct_dev"}), [
      "direct_exec_in_production"
    ])

    assert_codes(Map.merge(base_env(dir), %{"TREEDX_EXEC_BACKEND" => "external_worker"}), [
      "missing_exec_worker_url",
      "missing_exec_worker_secret"
    ])

    assert_codes(
      Map.merge(base_env(dir), %{
        "TREEDX_GIT_EXTERNAL_TRANSPORT_ENABLED" => "true",
        "TREEDX_REMOTE_CREDENTIAL_PROVIDER" => "none"
      }),
      ["missing_remote_credential_provider"]
    )

    assert_codes(
      Map.merge(base_env(dir), %{
        "TREEDX_GIT_SSH_ENABLED" => "true",
        "TREEDX_REMOTE_CREDENTIAL_PROVIDER" => "none"
      }),
      ["missing_ssh_known_hosts", "missing_remote_credential_provider"]
    )
  end

  test "rejects fallback secrets, unsafe restore, and invalid data directory", %{dir: dir} do
    assert_codes(Map.merge(base_env(dir), %{"SECRET_KEY_BASE" => String.duplicate("c", 64)}), [
      "fallback_secret_key_base"
    ])

    assert_codes(Map.merge(base_env(dir), %{"TREEDX_STORAGE_RESTORE_ENABLED" => "true"}), [
      "restore_ack_required"
    ])

    assert_codes(Map.merge(base_env(dir), %{"TREEDX_DATA_DIR" => "relative/path"}), [
      "relative_data_dir"
    ])
  end

  test "errors are sanitized", %{dir: dir} do
    {:error, errors} =
      ConfigValidation.validate_env(
        base_env(dir)
        |> Map.put("TREEDX_JWKS_URL", "https://user:password@example.test/jwks.json")
        |> Map.delete("TREEDX_JWT_ALLOWED_ALGS")
      )

    encoded = Jason.encode!(errors)
    refute encoded =~ "password"
    refute encoded =~ "https://user:password"
  end

  defp base_env(dir) do
    %{
      "MIX_ENV" => "prod",
      "TREEDX_ENV" => "prod",
      "SECRET_KEY_BASE" => String.duplicate("a", 64),
      "TREEDX_AUTH_MODE" => "connected",
      "TREEDX_AUTH_VERIFIER" => "jwks_oidc",
      "TREEDX_JWT_ISSUER" => "https://issuer.example.test",
      "TREEDX_JWT_AUDIENCE" => "treedx",
      "TREEDX_JWKS_URL" => "https://issuer.example.test/.well-known/jwks.json",
      "TREEDX_JWT_ALLOWED_ALGS" => "RS256",
      "TREEDX_EXEC_BACKEND" => "container_sandbox",
      "TREEDX_DATA_DIR" => dir
    }
  end

  defp assert_codes(env, expected_codes) do
    assert {:error, errors} = ConfigValidation.validate_env(env)
    codes = Enum.map(errors, & &1.code)

    for code <- expected_codes do
      assert code in codes
    end
  end
end
