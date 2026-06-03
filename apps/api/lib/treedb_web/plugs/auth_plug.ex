defmodule TreeDbWeb.AuthPlug do
  @moduledoc false
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id = get_req_header(conn, "x-request-id") |> List.first() || TreeDb.Ids.short("req")
    Logger.metadata(request_id: request_id)
    TreeDb.Observability.Metrics.incr("treedb_auth_attempts_total", %{status: "attempt"})

    case TreeDb.Auth.authenticate_header(get_req_header(conn, "authorization") |> List.first()) do
      {:ok, principal} ->
        if principal do
          Logger.metadata(actor_id: principal[:actorId] || principal["actorId"])
          Logger.metadata(tenant_id: principal[:tenantId] || principal["tenantId"])
          TreeDb.Observability.Metrics.incr("treedb_auth_attempts_total", %{status: "ok"})
        else
          Logger.metadata(actor_id: nil, tenant_id: nil)
          TreeDb.Observability.Metrics.incr("treedb_auth_attempts_total", %{status: "anonymous"})
        end

        conn
        |> put_resp_header("x-request-id", request_id)
        |> assign(:request_id, request_id)
        |> assign(:principal, stringify(principal))

      {:error, error} ->
        code = error[:code] || error["code"] || "invalid_token"
        TreeDb.Observability.Metrics.incr("treedb_auth_attempts_total", %{status: "error"})
        TreeDb.Observability.Metrics.incr("treedb_auth_failures_total", %{error_code: code})

        conn
        |> put_resp_header("x-request-id", request_id)
        |> assign(:request_id, request_id)
        |> assign(:auth_error, error)
        |> assign(:principal, nil)
    end
  end

  defp stringify(nil), do: nil
  defp stringify(map), do: for({key, value} <- map, into: %{}, do: {to_string(key), value})
end
