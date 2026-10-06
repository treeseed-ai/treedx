defmodule TreeDxWeb.BlobController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def read_repo(conn, %{"repo_id" => repo_id} = params),
    do:
      maybe_proxy_repo_read(conn, repo_id, params, [pool: :repository_query], fn conn ->
        with_principal(conn, &TreeDx.Blobs.read_repo(repo_id, params, &1))
      end)

  def write(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Blobs.write_workspace(workspace_id, params, &1))
      end)

  def delete(conn, %{"workspace_id" => workspace_id} = params),
    do:
      maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
        with_principal(conn, &TreeDx.Blobs.delete_workspace(workspace_id, params, &1))
      end)

  def download(conn, %{"workspace_id" => workspace_id} = params) do
    maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn),
           {:ok, blob} <- TreeDx.Blobs.download_workspace(workspace_id, params, principal) do
        conn
        |> put_resp_content_type(blob.contentType)
        |> put_resp_header(
          "content-disposition",
          ~s(attachment; filename="#{filename(blob.path)}")
        )
        |> put_resp_header("x-treedx-content-hash", blob.contentHash || "")
        |> maybe_put_header("x-treedx-object-id", blob.objectId)
        |> put_resp_header("x-treedx-source", blob.source || "")
        |> send_resp(200, blob.bytes)
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def upload(conn, %{"workspace_id" => workspace_id} = params) do
    with {:ok, bytes, conn} <- read_limited_body(conn) do
      case TreeDx.Federation.Proxy.maybe_proxy_workspace(workspace_id, conn, bytes) do
        :local ->
          with {:ok, principal} <- require_principal(conn),
               params <- upload_params(conn, params),
               {:ok, payload} <-
                 TreeDx.Blobs.upload_workspace(workspace_id, params, bytes, principal) do
            handle_result(conn, {:ok, payload})
          else
            {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
          end

        {:proxy, status, headers, body} ->
          send_proxy_response(conn, status, headers, body)

        {:error, error} ->
          error(conn, status_for(error[:code] || error["code"]), error)
      end
    else
      {:error, error} ->
        error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp with_principal(conn, fun) do
    with {:ok, principal} <- require_principal(conn) do
      handle_result(conn, fun.(principal))
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp read_limited_body(conn) do
    limit = TreeDx.Blobs.max_blob_bytes()

    case read_body(conn, length: limit + 1, read_length: limit + 1) do
      {:ok, body, conn} when byte_size(body) <= limit ->
        {:ok, body, conn}

      {:ok, _body, _conn} ->
        {:error, %{code: "payload_too_large", message: "Blob exceeds TREEDX_MAX_BLOB_BYTES."}}

      {:more, _body, _conn} ->
        {:error, %{code: "payload_too_large", message: "Blob exceeds TREEDX_MAX_BLOB_BYTES."}}

      {:error, reason} ->
        {:error,
         %{
           code: "validation_error",
           message: "Unable to read request body.",
           details: %{reason: inspect(reason)}
         }}
    end
  end

  defp upload_params(conn, params) do
    params
    |> Map.put(
      "contentType",
      List.first(get_req_header(conn, "content-type")) || params["contentType"]
    )
    |> Map.put(
      "expectedSha",
      List.first(get_req_header(conn, "x-treedx-expected-sha")) || params["expectedSha"]
    )
    |> Map.put(
      "expectedContentHash",
      List.first(get_req_header(conn, "x-treedx-expected-content-hash")) ||
        params["expectedContentHash"]
    )
    |> Map.put(
      "allowProtected",
      List.first(get_req_header(conn, "x-treedx-allow-protected")) || params["allowProtected"]
    )
  end

  defp maybe_put_header(conn, _name, nil), do: conn
  defp maybe_put_header(conn, _name, ""), do: conn
  defp maybe_put_header(conn, name, value), do: put_resp_header(conn, name, value)

  defp filename(path) do
    path
    |> Path.basename()
    |> String.replace(~r/["\\\r\n]/, "_")
  end
end
