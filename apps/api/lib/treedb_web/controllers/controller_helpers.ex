defmodule TreeDbWeb.ControllerHelpers do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  def ok(conn, payload), do: json(conn, Map.put(payload, :ok, true))

  def error(conn, status, error) do
    conn
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
  def status_for("permission_denied"), do: 403
  def status_for("not_found"), do: 404
  def status_for("graph_not_ready"), do: 404
  def status_for("payload_too_large"), do: 413
  def status_for("unsupported_media_type"), do: 415
  def status_for("conflict"), do: 409
  def status_for("not_implemented"), do: 501
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
