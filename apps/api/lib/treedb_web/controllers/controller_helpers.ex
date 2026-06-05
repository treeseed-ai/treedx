defmodule TreeDbWeb.ControllerHelpers do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  def ok(conn, payload), do: json(conn, Map.put(payload, :ok, true))

  def error(conn, status, error) do
    conn
    |> assign(:treedb_error_code, error[:code] || error["code"] || "internal_error")
    |> put_status(status)
    |> json(%{
      ok: false,
      error: %{
        code: error[:code] || error["code"] || "internal_error",
        message: error[:message] || error["message"] || "Internal error.",
        details: error[:details] || error["details"] || %{}
      }
    })
  end

  def status_for("authentication_required"), do: 401
  def status_for("invalid_token"), do: 401
  def status_for("token_expired"), do: 401
  def status_for("token_not_yet_valid"), do: 401
  def status_for("invalid_issuer"), do: 401
  def status_for("invalid_audience"), do: 401
  def status_for("invalid_signature"), do: 401
  def status_for("auth_not_configured"), do: 500
  def status_for("service_unavailable"), do: 503
  def status_for("server_busy"), do: 503
  def status_for("permission_denied"), do: 403
  def status_for("not_found"), do: 404
  def status_for("graph_not_ready"), do: 404
  def status_for("snapshot_not_found"), do: 404
  def status_for("artifact_not_found"), do: 404
  def status_for("payload_too_large"), do: 413
  def status_for("unsupported_media_type"), do: 415
  def status_for("conflict"), do: 409
  def status_for("workspace_revoked"), do: 409
  def status_for("migration_conflict"), do: 409
  def status_for("not_implemented"), do: 501
  def status_for("federated_scope_empty"), do: 403
  def status_for("federated_node_unavailable"), do: 502
  def status_for("federated_node_timeout"), do: 502
  def status_for("federated_partial_failure"), do: 502
  def status_for("federated_route_not_configured"), do: 502
  def status_for("write_route_required"), do: 409
  def status_for("federated_proxy_loop"), do: 508
  def status_for("federated_node_auth_required"), do: 401
  def status_for("federated_node_auth_invalid"), do: 401
  def status_for("federated_node_auth_forbidden"), do: 403
  def status_for("federated_mirror_stale"), do: 409
  def status_for("federated_mirror_unavailable"), do: 502
  def status_for("federated_catalog_rejected"), do: 422
  def status_for("federated_delegation_forbidden"), do: 403
  def status_for("idempotency_conflict"), do: 409
  def status_for("unsupported_transport"), do: 422
  def status_for("validation_error"), do: 422
  def status_for(_), do: 500

  def require_principal(conn) do
    case conn.assigns[:principal] do
      nil -> {:error, %{code: "authentication_required", message: "Authentication required."}}
      principal -> {:ok, principal}
    end
  end

  def handle_result(conn, {:ok, payload}), do: ok(conn, payload)

  def handle_result(conn, {:error, error}),
    do: error(conn, status_for(error[:code] || error["code"]), error)
end
