defmodule TreeDbWeb.AdminStorageController do
  use Phoenix.Controller, formats: [:json]
  import TreeDbWeb.ControllerHelpers

  def health(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:read") do
      handle_result(conn, TreeDb.AdminStorage.health())
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def check(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:read") do
      handle_result(conn, TreeDb.AdminStorage.check())
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def recover(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDb.AdminStorage.recover(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def compact(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDb.AdminStorage.compact(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def backup(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "policy:read") do
      handle_result(
        conn,
        TreeDb.AdminStorage.backup(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
