defmodule TreeDbWeb.AuthPlug do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id = get_req_header(conn, "x-request-id") |> List.first() || TreeDb.Ids.short("req")

    case TreeDb.Auth.authenticate_header(get_req_header(conn, "authorization") |> List.first()) do
      {:ok, principal} ->
        conn
        |> put_resp_header("x-request-id", request_id)
        |> assign(:request_id, request_id)
        |> assign(:principal, stringify(principal))

      {:error, error} ->
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
