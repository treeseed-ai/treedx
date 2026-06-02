defmodule TreeDbWeb.AuthController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def whoami(conn, _params) do
    principal = conn.assigns[:principal]
    ok(conn, %{authenticated: not is_nil(principal), principal: principal})
  end

  def dev_token(conn, params) do
    handle_result(conn, TreeDb.Auth.create_dev_token(params))
  end

  def mode(conn, _params) do
    ok(conn, TreeDb.Auth.auth_mode_payload())
  end
end
