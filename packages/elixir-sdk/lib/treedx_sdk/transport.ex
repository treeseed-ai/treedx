defmodule TreeDxSdk.Transport.Request do
  @moduledoc false
  defstruct [:method, :path, query: %{}, headers: %{}, body: nil, binary_body: nil]
end

defmodule TreeDxSdk.Transport.Response do
  @moduledoc false
  defstruct [:status, headers: %{}, data: nil]
end

defmodule TreeDxSdk.Transport do
  @moduledoc false
  @callback request(TreeDxSdk.Config.t(), TreeDxSdk.Transport.Request.t()) ::
              {:ok, TreeDxSdk.Transport.Response.t()} | {:error, TreeDxSdk.Error.t()}
end

defmodule TreeDxSdk.Transport.Httpc do
  @moduledoc false
  @behaviour TreeDxSdk.Transport

  @impl true
  def request(config, request) do
    with {:ok, url} <- build_url(config, request),
         {:ok, headers} <- build_headers(config, request),
         {:ok, body, content_type} <- build_body(request) do
      method = request.method |> to_string() |> String.downcase() |> String.to_atom()

      http_request =
        if content_type,
          do: {String.to_charlist(url), headers, content_type, body},
          else: {String.to_charlist(url), headers}

      options = if config.timeout, do: [timeout: config.timeout], else: []

      case :httpc.request(method, http_request, options, body_format: :binary) do
        {:ok, {{_, status, _}, response_headers, response_body}} ->
          decode_response(status, response_headers, response_body)

        {:error, reason} ->
          {:error, TreeDxSdk.Error.network(inspect(reason))}
      end
    end
  end

  defp build_url(%TreeDxSdk.Config{base_url: base_url}, request) when is_binary(base_url) do
    base = String.trim_trailing(base_url, "/")
    query = URI.encode_query(request.query || %{})
    url = base <> request.path
    {:ok, if(query == "", do: url, else: url <> "?" <> query)}
  end

  defp build_url(_, _), do: {:error, TreeDxSdk.Error.network("TreeDX base_url is required")}

  defp build_headers(config, request) do
    headers = Map.merge(config.default_headers || %{}, request.headers || %{})

    with {:ok, auth_header} <- TreeDxSdk.Auth.resolve_authorization_header(config) do
      headers =
        if auth_header,
          do: Map.put(headers, elem(auth_header, 0), elem(auth_header, 1)),
          else: headers

      {:ok,
       Enum.map(headers, fn {key, value} ->
         {String.to_charlist(to_string(key)), String.to_charlist(to_string(value))}
       end)}
    end
  end

  defp build_body(%{binary_body: body}) when not is_nil(body),
    do: {:ok, TreeDxSdk.Binary.to_binary(body), ~c"application/octet-stream"}

  defp build_body(%{body: nil}), do: {:ok, ~c"", nil}
  defp build_body(%{body: body}), do: {:ok, Jason.encode!(body), ~c"application/json"}

  defp decode_response(status, headers, body) do
    header_map = Map.new(headers, fn {key, value} -> {to_string(key), to_string(value)} end)

    content_type =
      header_map
      |> Enum.find_value("", fn {key, value} ->
        if String.downcase(key) == "content-type", do: value
      end)

    data = decode_body(content_type, body)

    if status in 200..299 do
      {:ok, %TreeDxSdk.Transport.Response{status: status, headers: header_map, data: data}}
    else
      {:error, TreeDxSdk.Error.from_response(status, data)}
    end
  end

  defp decode_body(content_type, body) do
    cond do
      String.contains?(content_type, "application/json") -> Jason.decode!(body)
      String.starts_with?(content_type, "text/") -> body
      true -> nil
    end
  end
end
