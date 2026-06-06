defmodule TreeDxSdk.Client do
  @moduledoc false
  defstruct [:config]

  def new(opts) do
    %__MODULE__{
      config: %TreeDxSdk.Config{
        base_url: Keyword.get(opts, :base_url),
        token: Keyword.get(opts, :token),
        auth_provider: Keyword.get(opts, :auth_provider),
        transport: Keyword.get(opts, :transport),
        default_headers: Keyword.get(opts, :default_headers, %{}),
        timeout: Keyword.get(opts, :timeout)
      }
    }
  end

  def health(client), do: TreeDxSdk.Observability.health(client)
  def version(client), do: TreeDxSdk.Adapters.Common.json_request(client, :get, "/api/v1/version")

  def whoami(client),
    do: TreeDxSdk.Adapters.Common.json_request(client, :get, "/api/v1/auth/whoami")

  def effective_scope(client),
    do: TreeDxSdk.Adapters.Common.json_request(client, :get, "/api/v1/policy/effective-scope")

  def auth_mode(client),
    do: TreeDxSdk.Adapters.Common.json_request(client, :get, "/api/v1/auth/mode")

  def create_dev_token(client, body \\ %{}),
    do: TreeDxSdk.Adapters.Common.json_request(client, :post, "/api/v1/auth/dev-token", body)

  def operation(client, method, path, opts \\ []) do
    method_text = method |> to_string() |> String.upcase()

    known? =
      TreeDxSdk.Generated.OpenApiTypes.operations()
      |> Enum.any?(fn operation -> operation.method == method_text and operation.path == path end)

    if known? do
      path_params = Keyword.get(opts, :path_params, %{})

      resolved =
        Regex.replace(~r/\{([^}]+)\}/, path, fn _, name ->
          value = Map.get(path_params, name) || Map.get(path_params, String.to_atom(name))

          if is_nil(value),
            do: raise(ArgumentError, "missing path parameter #{name} for #{method_text} #{path}")

          TreeDxSdk.Adapters.Common.segment(value)
        end)

      TreeDxSdk.Adapters.Common.json_request(
        client,
        method_text |> String.downcase() |> String.to_atom(),
        resolved,
        Keyword.get(opts, :body),
        Keyword.get(opts, :query, %{})
      )
    else
      raise ArgumentError, "unknown TreeDX OpenAPI operation: #{method_text} #{path}"
    end
  end
end
