defmodule TreeDxWeb.AuthController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def whoami(conn, _params) do
    principal = conn.assigns[:principal]
    ok(conn, %{authenticated: not is_nil(principal), principal: principal})
  end

  def dev_token(conn, params) do
    handle_result(conn, TreeDx.Auth.create_dev_token(params))
  end

  def mode(conn, _params) do
    ok(conn, TreeDx.Auth.auth_mode_payload())
  end
end
