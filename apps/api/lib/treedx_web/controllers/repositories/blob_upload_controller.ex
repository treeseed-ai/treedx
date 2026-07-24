defmodule TreeDxWeb.BlobUploadController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def create(conn, %{"workspace_id" => workspace_id} = params) do
    maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Uploads.create(workspace_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def part(conn, %{
        "workspace_id" => workspace_id,
        "upload_id" => upload_id,
        "part_number" => part_number
      }) do
    with {:ok, bytes, conn} <- read_limited_body(conn) do
      case TreeDx.Federation.Proxy.maybe_proxy_workspace(workspace_id, conn, bytes) do
        :local ->
          with {:ok, principal} <- require_principal(conn),
               {:ok, payload} <-
                 TreeDx.Uploads.put_part(workspace_id, upload_id, part_number, bytes, principal) do
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

  def complete(conn, %{"workspace_id" => workspace_id, "upload_id" => upload_id} = params) do
    maybe_proxy_workspace(conn, workspace_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Uploads.complete(workspace_id, upload_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def abort(conn, %{"workspace_id" => workspace_id, "upload_id" => upload_id}) do
    maybe_proxy_workspace(conn, workspace_id, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Uploads.abort(workspace_id, upload_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  defp read_limited_body(conn) do
    limit =
      System.get_env("TREEDX_MULTIPART_PART_BYTES", "8388608")
      |> Integer.parse()
      |> case do
        {value, _} when value > 0 -> value
        _ -> 8_388_608
      end

    case read_body(conn, length: limit + 1, read_length: limit + 1) do
      {:ok, body, conn} when byte_size(body) <= limit ->
        {:ok, body, conn}

      {:ok, _body, _conn} ->
        {:error, %{code: "payload_too_large", message: "Upload part is too large."}}

      {:more, _body, _conn} ->
        {:error, %{code: "payload_too_large", message: "Upload part is too large."}}

      {:error, _reason} ->
        {:error, %{code: "validation_error", message: "Unable to read request body."}}
    end
  end
end
