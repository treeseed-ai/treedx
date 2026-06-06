defmodule TreeDxWeb.FederationProxyHelpers do
  @moduledoc false

  import Plug.Conn
  import TreeDxWeb.ControllerHelpers

  def maybe_proxy_repo_read(conn, repo_id, fun) when is_function(fun, 1),
    do: maybe_proxy_repo_read(conn, repo_id, nil, [], fun)

  def maybe_proxy_repo_read(conn, repo_id, body, fun) when is_function(fun, 1),
    do: maybe_proxy_repo_read(conn, repo_id, body, [], fun)

  def maybe_proxy_repo_read(conn, repo_id, body, opts, fun) when is_function(fun, 1) do
    case TreeDx.Federation.Proxy.maybe_proxy_repo_read(repo_id, conn, body, opts) do
      :local -> fun.(conn)
      {:proxy, status, headers, body} -> send_proxy_response(conn, status, headers, body)
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def maybe_proxy_repo_write(conn, repo_id, fun) when is_function(fun, 1),
    do: maybe_proxy_repo_write(conn, repo_id, nil, [], fun)

  def maybe_proxy_repo_write(conn, repo_id, body, fun) when is_function(fun, 1),
    do: maybe_proxy_repo_write(conn, repo_id, body, [], fun)

  def maybe_proxy_repo_write(conn, repo_id, body, opts, fun) when is_function(fun, 1) do
    case TreeDx.Federation.Proxy.maybe_proxy_repo_write(repo_id, conn, body, opts) do
      :local -> fun.(conn)
      {:proxy, status, headers, body} -> send_proxy_response(conn, status, headers, body)
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def maybe_proxy_workspace(conn, workspace_id, body \\ nil, fun) when is_function(fun, 1) do
    case TreeDx.Federation.Proxy.maybe_proxy_workspace(workspace_id, conn, body) do
      :local -> fun.(conn)
      {:proxy, status, headers, body} -> send_proxy_response(conn, status, headers, body)
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def send_proxy_response(conn, status, headers, body) do
    maybe_store_workspace_route(status, body)

    conn =
      headers
      |> Enum.reduce(conn, fn
        %{"name" => key, "value" => value}, acc -> maybe_put_resp_header(acc, key, value)
        {key, value}, acc -> maybe_put_resp_header(acc, to_string(key), to_string(value))
        [key, value], acc -> maybe_put_resp_header(acc, to_string(key), to_string(value))
        _, acc -> acc
      end)

    send_resp(conn, status, body || "")
  end

  defp maybe_store_workspace_route(status, body) when status in 200..299 and is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body),
         workspace_id when is_binary(workspace_id) <-
           decoded["workspaceId"] || decoded["workspace_id"],
         repo_id when is_binary(repo_id) <- decoded["repoId"] || decoded["repositoryId"],
         node_id when is_binary(node_id) <- decoded["nodeId"] do
      TreeDx.Store.put_workspace_route(%{
        workspaceId: workspace_id,
        repositoryId: repo_id,
        nodeId: node_id,
        actorId: "",
        status: decoded["status"] || "open",
        createdAt: DateTime.utc_now() |> DateTime.to_iso8601(),
        updatedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
        expiresAt: decoded["expiresAt"]
      })
    else
      _ -> :ok
    end
  end

  defp maybe_store_workspace_route(_status, _body), do: :ok

  defp maybe_put_resp_header(conn, key, value) do
    downcased = String.downcase(key)

    if downcased in ["content-length", "transfer-encoding", "connection"] do
      conn
    else
      put_resp_header(conn, downcased, value)
    end
  end
end
