defmodule TreeDbWeb.InternalFederationController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def proxy(conn, params) do
    with {:ok, node_payload} <- TreeDb.Federation.NodeAuth.verify_conn(conn, "proxy"),
         {:ok, request} <- normalize_proxy_request(params),
         :ok <- reject_blocked_proxy_path(request),
         :ok <- reject_absolute_path_payload(request),
         {:ok, idempotency_result} <- idempotency_preflight(request),
         {:ok, status, headers, body} <- dispatch_local(request, node_payload),
         :ok <- idempotency_store(idempotency_result, request, status, headers, body) do
      json(conn, %{
        ok: true,
        status: status,
        headers: sanitize_headers(headers),
        body: Base.encode64(body || ""),
        bodyEncoding: "base64",
        servedByNodeId: TreeDb.Federation.NodeIdentity.node_id()
      })
    else
      {:cached, response} ->
        json(conn, response)

      {:error, error} ->
        error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def mirror_export(conn, %{"repo_id" => repo_id}) do
    with {:ok, _node_payload} <- TreeDb.Federation.NodeAuth.verify_conn(conn, "mirror_export"),
         {:ok, export} <- TreeDb.Federation.MirrorTransfer.export(repo_id) do
      ok(conn, export)
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def mirror_import(conn, %{"repo_id" => repo_id} = params) do
    with {:ok, node_payload} <- TreeDb.Federation.NodeAuth.verify_conn(conn, "mirror_import"),
         {:ok, import} <- TreeDb.Federation.MirrorTransfer.import(repo_id, params, node_payload) do
      ok(conn, import)
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def health(conn, _params) do
    with {:ok, _node_payload} <- TreeDb.Federation.NodeAuth.verify_conn(conn, "health") do
      ok(conn, %{
        nodeId: TreeDb.Federation.NodeIdentity.node_id(),
        federation: %{status: "healthy"},
        runtime: %{
          pressure: to_string(TreeDb.Runtime.Resources.memory_snapshot().pressure),
          memory: TreeDb.Runtime.Resources.memory_snapshot()
        },
        pools: TreeDb.Runtime.Pool.snapshot()
      })
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp normalize_proxy_request(params) do
    request = %{
      method: String.upcase(to_string(params["method"] || "")),
      path: to_string(params["path"] || ""),
      query_string: to_string(params["queryString"] || ""),
      headers: params["headers"] || %{},
      body: params["body"],
      body_encoding: params["bodyEncoding"] || "empty",
      idempotency_key: params["idempotencyKey"],
      original_request_id: params["originalRequestId"]
    }

    if request.method in ~w(GET POST PUT PATCH DELETE) and
         String.starts_with?(request.path, "/api/v1/") do
      {:ok, request}
    else
      {:error, %{code: "validation_error", message: "Invalid federated proxy request."}}
    end
  end

  defp reject_blocked_proxy_path(%{path: path}) do
    cond do
      path == "/api/v1/internal/federation/proxy" ->
        {:error, %{code: "federated_proxy_loop", message: "Federated proxy loop rejected."}}

      path == "/api/v1/admin/storage/restore" ->
        {:error, %{code: "federated_route_not_configured", message: "Route cannot be proxied."}}

      path == "/api/v1/admin/repos/import-local" ->
        {:error, %{code: "federated_route_not_configured", message: "Route cannot be proxied."}}

      true ->
        :ok
    end
  end

  defp reject_absolute_path_payload(%{body: body}) do
    body
    |> inspect()
    |> then(fn encoded ->
      if String.contains?(encoded, ["localPath", TreeDb.Store.data_dir()]) do
        {:error,
         %{code: "validation_error", message: "Federated proxy payload contains local paths."}}
      else
        :ok
      end
    end)
  end

  defp idempotency_preflight(%{method: method} = request)
       when method in ~w(POST PUT PATCH DELETE) do
    key = request.idempotency_key || "proxy:#{System.unique_integer([:positive])}"
    fingerprint = request_fingerprint(request)

    case TreeDb.Store.get_idempotency_record(key) do
      {:ok, %{"responseJson" => response_json, "bodyHash" => ^fingerprint}}
      when is_map(response_json) ->
        {:cached, response_json}

      {:ok, record} when is_map(record) ->
        {:error, %{code: "idempotency_conflict", message: "Idempotency key payload mismatch."}}

      _ ->
        {:ok, %{key: key, fingerprint: fingerprint}}
    end
  end

  defp idempotency_preflight(_request), do: {:ok, nil}

  defp idempotency_store(nil, _request, _status, _headers, _body), do: :ok

  defp idempotency_store(%{key: key, fingerprint: fingerprint}, request, status, headers, body) do
    response = %{
      ok: true,
      status: status,
      headers: sanitize_headers(headers),
      body: Base.encode64(body || ""),
      bodyEncoding: "base64",
      servedByNodeId: TreeDb.Federation.NodeIdentity.node_id()
    }

    TreeDb.Store.put_idempotency_record(%{
      id: key,
      method: request.method,
      path: request.path,
      bodyHash: fingerprint,
      status: "stored",
      responseJson: response,
      createdAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      expiresAt: DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_iso8601()
    })

    :ok
  end

  defp dispatch_local(request, _node_payload) do
    url =
      "http://127.0.0.1:#{System.get_env("PORT") || "4000"}" <>
        request.path <>
        if(request.query_string == "", do: "", else: "?" <> request.query_string)

    headers =
      request.headers
      |> Map.put("x-treedb-internal-dispatch", "true")
      |> Map.put("x-treedb-forward-hop", "0")
      |> maybe_put_local_dev_authorization()
      |> Enum.map(fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(to_string(value))}
      end)

    body = decode_proxy_body(request)

    case :httpc.request(
           request.method |> String.downcase() |> String.to_atom(),
           request_tuple(request.method, url, headers, body),
           [timeout: 30_000],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, headers, body}} ->
        {:ok, status, headers, body}

      {:error, reason} ->
        {:error, %{code: "federated_node_unavailable", message: inspect(reason)}}
    end
  end

  defp decode_proxy_body(%{body_encoding: "base64", body: body}) when is_binary(body),
    do: Base.decode64!(body)

  defp decode_proxy_body(%{body_encoding: "json", body: body}), do: Jason.encode!(body || %{})
  defp decode_proxy_body(_), do: ""

  defp content_type(headers) do
    headers
    |> Enum.find_value(~c"application/json", fn {key, value} ->
      if String.downcase(to_string(key)) == "content-type", do: value
    end)
  end

  defp request_tuple("GET", url, headers, _body), do: {String.to_charlist(url), headers}

  defp request_tuple(_method, url, headers, body),
    do: {String.to_charlist(url), headers, content_type(headers), body}

  defp maybe_put_local_dev_authorization(headers) do
    if TreeDb.Auth.mode() == "dev" do
      case TreeDb.Auth.create_dev_token(%{
             actorId: "actor_demo",
             tenantId: "tenant_demo",
             expiresInSeconds: 300
           }) do
        {:ok, %{accessToken: token}} -> Map.put(headers, "authorization", "Bearer #{token}")
        _ -> headers
      end
    else
      headers
    end
  end

  defp request_fingerprint(request) do
    :crypto.hash(
      :sha256,
      Jason.encode!(Map.take(request, [:method, :path, :query_string, :body]))
    )
    |> Base.url_encode64(padding: false)
  end

  defp sanitize_headers(headers) do
    Enum.flat_map(headers, fn
      {key, value} ->
        key = to_string(key) |> String.downcase()

        if key in ["authorization", "x-treedb-node-authorization", "set-cookie"] do
          []
        else
          [%{name: key, value: to_string(value)}]
        end

      _ ->
        []
    end)
  end
end
