defmodule TreeDx.Auth.Verifier do
  @moduledoc false

  @verifiers %{
    "hs256_dev" => TreeDx.Auth.Verifiers.Hs256Dev,
    "jwks_oidc" => TreeDx.Auth.Verifiers.JwksOidc,
    "trusted_internal" => nil
  }

  def type do
    TreeDx.Env.get("TREEDX_AUTH_VERIFIER") || legacy_default()
  end

  def verify(token) do
    case verifier_module() do
      {:ok, module} -> module.verify(token)
      {:error, error} -> {:error, error}
    end
  end

  def validate_config do
    with :ok <- validate_runtime_safety() do
      case verifier_module() do
        {:ok, module} -> module.validate_config()
        {:error, error} -> {:error, error}
      end
    end
  end

  def info do
    case verifier_module() do
      {:ok, module} -> module.info()
      {:error, _error} -> %{type: type()}
    end
  end

  defp validate_runtime_safety do
    if type() == "hs256_dev" && prod_runtime?() &&
         TreeDx.Env.get("TREEDX_ALLOW_DEV_VERIFIER_IN_PROD") != "true" do
      {:error,
       %{
         code: "auth_not_configured",
         message: "hs256_dev verifier is not allowed in production without explicit override."
       }}
    else
      :ok
    end
  end

  defp prod_runtime? do
    System.get_env("MIX_ENV") == "prod" || System.get_env("PHX_SERVER") == "true"
  end

  defp verifier_module do
    case Map.fetch(@verifiers, type()) do
      {:ok, nil} ->
        {:error,
         %{
           code: "auth_not_configured",
           message: "trusted_internal verifier is not implemented for this runtime."
         }}

      {:ok, module} ->
        {:ok, module}

      :error ->
        {:error,
         %{
           code: "auth_not_configured",
           message: "Unsupported auth verifier: #{inspect(type())}."
         }}
    end
  end

  defp legacy_default do
    if TreeDx.Env.get("TREEDX_JWT_HS256_SECRET"), do: "hs256_dev", else: nil
  end
end
