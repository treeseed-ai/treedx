defmodule TreeDxSdk.AuthProvider do
  @moduledoc false
  @callback get_token(term()) :: {:ok, String.t()} | {:error, term()}
end

defmodule TreeDxSdk.Auth do
  @moduledoc false

  def static_bearer_token_provider(token), do: {:static_bearer_token, token}

  def resolve_authorization_header(%TreeDxSdk.Config{auth_provider: provider})
      when not is_nil(provider) do
    with {:ok, token} <- resolve_provider(provider) do
      {:ok, {"Authorization", "Bearer #{token}"}}
    end
  end

  def resolve_authorization_header(%TreeDxSdk.Config{token: token}) when is_binary(token) do
    {:ok, {"Authorization", "Bearer #{token}"}}
  end

  def resolve_authorization_header(%TreeDxSdk.Config{}), do: {:ok, nil}

  defp resolve_provider({:static_bearer_token, token}), do: {:ok, token}
  defp resolve_provider({module, state}) when is_atom(module), do: module.get_token(state)
  defp resolve_provider(fun) when is_function(fun, 0), do: {:ok, fun.()}
  defp resolve_provider(fun) when is_function(fun, 1), do: fun.(:token)
end
