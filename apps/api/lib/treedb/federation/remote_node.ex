defmodule TreeDb.Federation.RemoteNode do
  @moduledoc false

  @default_timeout 5_000

  def execute(operation, allowed, params, auth_header) do
    with :ok <- remote_enabled?(),
         base_url when is_binary(base_url) and base_url != "" <- allowed.baseUrl,
         {:ok, endpoint} <- endpoint(operation, allowed.repoId),
         {:ok, body} <- Jason.encode(remote_body(allowed, params, operation)),
         {:ok, response} <- request(base_url, endpoint, body, auth_header, timeout(params)) do
      unwrap_response(operation, response)
    else
      :disabled -> {:error, remote_error(allowed, "federated_route_not_configured")}
      nil -> {:error, remote_error(allowed, "federated_route_not_configured")}
      "" -> {:error, remote_error(allowed, "federated_route_not_configured")}
      {:error, %{code: code}} -> {:error, remote_error(allowed, code)}
      {:error, code} when is_binary(code) -> {:error, remote_error(allowed, code)}
      _ -> {:error, remote_error(allowed, "federated_node_unavailable")}
    end
  end

  defp remote_enabled? do
    if System.get_env("TREEDB_FEDERATION_ENABLE_REMOTE_HTTP", "true") in ["false", "0"] do
      :disabled
    else
      :ok
    end
  end

  defp endpoint(:search, repo_id), do: {:ok, "/api/v1/repos/#{URI.encode(repo_id)}/files/search"}
  defp endpoint(:query, repo_id), do: {:ok, "/api/v1/repos/#{URI.encode(repo_id)}/query"}

  defp endpoint(:context, repo_id),
    do: {:ok, "/api/v1/repos/#{URI.encode(repo_id)}/context/build"}

  defp endpoint(:graph, repo_id), do: {:ok, "/api/v1/repos/#{URI.encode(repo_id)}/graph/query"}
  defp endpoint(_, _), do: {:error, %{code: "validation_error"}}

  defp remote_body(allowed, params, operation) do
    params
    |> Map.take([
      "query",
      "type",
      "filters",
      "sort",
      "options",
      "budget",
      "seedIds",
      "seeds",
      "relations",
      "scopePaths",
      "allowProtected",
      "baseRef"
    ])
    |> Map.put("ref", allowed.ref)
    |> Map.put("paths", allowed.paths)
    |> Map.put("limit", per_repo_limit(params))
    |> Map.put_new("type", if(operation == :query, do: params["type"] || "text", else: nil))
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp request(base_url, endpoint, body, auth_header, timeout_ms) do
    url = String.trim_trailing(base_url, "/") <> endpoint
    headers = [{~c"accept", ~c"application/json"}, {~c"content-type", ~c"application/json"}]

    headers =
      if forward_auth?() and is_binary(auth_header) and auth_header != "" do
        [{~c"authorization", to_charlist(auth_header)} | headers]
      else
        headers
      end

    options = [timeout: timeout_ms]
    http_options = [body_format: :binary]

    case :httpc.request(
           :post,
           {to_charlist(url), headers, ~c"application/json", body},
           options,
           http_options
         ) do
      {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
        Jason.decode(response_body)

      {:ok, {{_, 408, _}, _headers, _body}} ->
        {:error, "federated_node_timeout"}

      {:ok, {{_, _status, _}, _headers, _body}} ->
        {:error, "federated_node_unavailable"}

      {:error, {:timeout, _}} ->
        {:error, "federated_node_timeout"}

      {:error, :timeout} ->
        {:error, "federated_node_timeout"}

      {:error, _} ->
        {:error, "federated_node_unavailable"}
    end
  end

  defp unwrap_response(_operation, %{"ok" => false}), do: {:error, "federated_node_unavailable"}

  defp unwrap_response(:search, response),
    do: {:ok, response["search"] || Map.delete(response, "ok")}

  defp unwrap_response(:query, response),
    do: {:ok, response["query"] || Map.delete(response, "ok")}

  defp unwrap_response(:context, response),
    do: {:ok, response["context"] || Map.delete(response, "ok")}

  defp unwrap_response(:graph, response),
    do: {:ok, response["graph"] || Map.delete(response, "ok")}

  defp remote_error(allowed, code) do
    %{
      repoId: allowed.repoId,
      nodeId: allowed.nodeId,
      code: code,
      message: message(code),
      source: "remote"
    }
  end

  defp message("federated_node_timeout"), do: "Federated node timed out."
  defp message("federated_route_not_configured"), do: "Federated route is not configured."
  defp message(_), do: "Federated node was unavailable."

  defp timeout(params) do
    requested = params["timeoutMs"] || System.get_env("TREEDB_FEDERATION_HTTP_TIMEOUT_MS")

    case Integer.parse(to_string(requested || @default_timeout)) do
      {int, ""} when int > 0 -> int
      _ -> @default_timeout
    end
  end

  defp per_repo_limit(params), do: min((params["limit"] || 20) * 2, 100)

  defp forward_auth?,
    do: System.get_env("TREEDB_FEDERATION_FORWARD_AUTH", "true") not in ["false", "0"]
end
