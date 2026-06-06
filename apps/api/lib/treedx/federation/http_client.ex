defmodule TreeDx.Federation.HttpClient do
  @moduledoc false

  @timeout 30_000

  def get_json(target_node_id, base_url, path, operation) do
    request(target_node_id, base_url, operation, :get, path, "", %{}, nil)
  end

  def post_json(target_node_id, base_url, path, operation, body) do
    request(target_node_id, base_url, operation, :post, path, "", %{}, body)
  end

  def request(target_node_id, base_url, operation, method, path, query_string, headers, body) do
    url =
      base_url
      |> String.trim_trailing("/")
      |> Kernel.<>(path)
      |> Kernel.<>(if(query_string in [nil, ""], do: "", else: "?" <> query_string))

    encoded_body = encode_body(body)

    http_headers =
      headers
      |> Map.new()
      |> Map.put_new("accept", "application/json")
      |> Map.put_new("content-type", "application/json")
      |> Map.put(
        "x-treedx-node-authorization",
        "Bearer " <> TreeDx.Federation.NodeAuth.issue(operation, target_node_id)
      )
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(to_string(value))}
      end)

    case :httpc.request(
           method,
           request_tuple(method, url, http_headers, encoded_body),
           [timeout: @timeout],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, response_headers, response_body}} ->
        {:ok, status, response_headers, response_body}

      {:error, reason} ->
        {:error,
         %{
           code: "federated_node_unavailable",
           message: "Federated node was unavailable.",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp encode_body(nil), do: ""
  defp encode_body(body) when is_binary(body), do: body
  defp encode_body(body), do: Jason.encode!(body)

  defp request_tuple(:get, url, headers, _body), do: {String.to_charlist(url), headers}

  defp request_tuple(method, url, headers, body) when method in [:post, :put, :patch, :delete],
    do: {String.to_charlist(url), headers, ~c"application/json", body}
end
