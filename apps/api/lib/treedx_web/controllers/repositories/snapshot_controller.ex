defmodule TreeDxWeb.SnapshotController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import TreeDxWeb.ControllerHelpers
  import TreeDxWeb.FederationProxyHelpers

  def build(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Snapshots.build(repo_id, params, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def show(conn, %{"repo_id" => repo_id, "snapshot_id" => snapshot_id}) do
    maybe_proxy_repo_read(conn, repo_id, nil, [pool: :snapshot, allow_mirrors?: false], fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        handle_result(conn, TreeDx.Snapshots.get(repo_id, snapshot_id, principal))
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  def export(conn, %{"repo_id" => repo_id} = params) do
    maybe_proxy_repo_write(conn, repo_id, params, fn conn ->
      with {:ok, principal} <- require_principal(conn) do
        if download?(params) do
          case TreeDx.Snapshots.download(repo_id, params, principal) do
            {:ok, %{artifact: artifact, snapshot: snapshot, bytes: bytes}} ->
              filename = "treedx-#{repo_id}-#{snapshot["snapshotId"]}.tar.zst"

              conn
              |> put_resp_content_type("application/zstd")
              |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
              |> put_resp_header("x-treedx-snapshot-id", snapshot["snapshotId"])
              |> put_resp_header("x-treedx-artifact-checksum", artifact["checksum"])
              |> send_resp(200, bytes)

            {:error, error} ->
              error(conn, status_for(error[:code] || error["code"]), error)
          end
        else
          handle_result(conn, TreeDx.Snapshots.export(repo_id, params, principal))
        end
      else
        {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
      end
    end)
  end

  defp download?(%{"download" => true}), do: true
  defp download?(%{"download" => "true"}), do: true
  defp download?(_params), do: false
end
