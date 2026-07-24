defmodule TreeDxWeb.AdminStorageController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def health(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(conn, TreeDx.AdminStorage.health())
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def check(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(conn, TreeDx.AdminStorage.check())
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def recover(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDx.AdminStorage.recover(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def compact(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDx.AdminStorage.compact(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def backup(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(
        conn,
        TreeDx.AdminStorage.backup(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def migrations(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(conn, TreeDx.AdminStorage.migrations())
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def plan_migration(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(
        conn,
        TreeDx.AdminStorage.plan_migration(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def apply_migration(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDx.AdminStorage.apply_migration(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def rollback_migration(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDx.AdminStorage.rollback_migration(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def verify_restore(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      handle_result(
        conn,
        TreeDx.AdminStorage.verify_restore(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def restore(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:write") do
      handle_result(
        conn,
        TreeDx.AdminStorage.restore(params, principal, conn.assigns[:request_id])
      )
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end
end
