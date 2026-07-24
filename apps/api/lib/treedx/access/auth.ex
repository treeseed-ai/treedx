defmodule TreeDx.Auth do
  @moduledoc false

  def mode, do: TreeDx.Env.get("TREEDX_AUTH_MODE") || "dev"

  def create_dev_token(params \\ %{}) do
    if mode() != "dev" do
      {:error, %{code: "not_implemented", message: "Dev tokens are only available in dev mode."}}
    else
      with {:ok, actor_id} <-
             configured_dev_principal(
               Map.get(params, "actorId") || Map.get(params, :actor_id),
               :actor_id,
               "TREEDX_DEV_ACTOR_ID"
             ),
           {:ok, tenant_id} <-
             configured_dev_principal(
               Map.get(params, "tenantId") || Map.get(params, :tenant_id),
               :tenant_id,
               "TREEDX_DEV_TENANT_ID"
             ) do
        ttl = Map.get(params, "expiresInSeconds") || Map.get(params, :expires_in_seconds) || 3600
        token = TreeDx.Ids.token()
        {:ok, token_hash} = TreeDx.Store.hash_token(token)
        expires_at = DateTime.utc_now() |> DateTime.add(ttl, :second) |> DateTime.to_iso8601()

        {:ok, _} =
          TreeDx.Store.put_dev_token(%{
            tokenHash: token_hash,
            actorId: actor_id,
            tenantId: tenant_id,
            expiresAt: expires_at,
            createdAt: DateTime.utc_now() |> DateTime.to_iso8601()
          })

        TreeDx.Audit.append("auth.dev_token_created", %{actor_id: actor_id, tenant_id: tenant_id})

        {:ok,
         %{
           accessToken: token,
           tokenType: "Bearer",
           expiresAt: expires_at,
           principal: principal(actor_id, tenant_id)
         }}
      end
    end
  end

  def authenticate_header(nil), do: {:ok, nil}

  def authenticate_header("Bearer " <> token), do: authenticate_token(token)

  def authenticate_header(_),
    do: {:error, %{code: "invalid_authorization", message: "Invalid authorization header."}}

  def authenticate_token(token) do
    if mode() == "connected" do
      TreeDx.Auth.Connected.authenticate(token)
    else
      authenticate_dev_token(token)
    end
  end

  def auth_mode_payload do
    case mode() do
      "connected" ->
        %{mode: "connected", connected: true, verifier: TreeDx.Auth.Connected.verifier_info()}

      _ ->
        %{mode: "dev", connected: false}
    end
  end

  def validate_boot_config do
    if mode() == "connected" do
      TreeDx.Auth.Connected.validate_config()
    else
      :ok
    end
  end

  defp authenticate_dev_token(token) do
    with {:ok, token_hash} <- TreeDx.Store.hash_token(token),
         {:ok, record} when is_map(record) <- TreeDx.Store.get_dev_token_by_hash(token_hash),
         {:ok, expires_at, _} <- DateTime.from_iso8601(record["expiresAt"]) do
      if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
        {:ok, principal(record["actorId"], record["tenantId"])}
      else
        {:error, %{code: "token_expired", message: "Token has expired."}}
      end
    else
      {:ok, nil} -> {:error, %{code: "invalid_token", message: "Invalid bearer token."}}
      {:error, error} when is_map(error) -> {:error, error}
      _ -> {:error, %{code: "invalid_token", message: "Invalid bearer token."}}
    end
  end

  def principal(actor_id, tenant_id) do
    TreeDx.Auth.Principal.from_dev(actor_id, tenant_id)
  end

  def dev_principal do
    with {:ok, actor_id} <- configured_dev_principal(nil, :actor_id, "TREEDX_DEV_ACTOR_ID"),
         {:ok, tenant_id} <- configured_dev_principal(nil, :tenant_id, "TREEDX_DEV_TENANT_ID") do
      {:ok, principal(actor_id, tenant_id)}
    end
  end

  defp configured_dev_principal(value, _key, _env) when is_binary(value) and value != "",
    do: {:ok, value}

  defp configured_dev_principal(_value, key, env) do
    configured =
      Application.get_env(:treedx, :dev_principal, [])
      |> Keyword.get(key)

    env_value = TreeDx.Env.get(env)

    cond do
      is_binary(configured) and configured != "" ->
        {:ok, configured}

      is_binary(env_value) and env_value != "" ->
        {:ok, env_value}

      true ->
        {:error,
         %{
           code: "configuration_error",
           message: "#{env} must be configured before using TreeDX dev authentication."
         }}
    end
  end
end
