defmodule TreeDxWeb.HealthController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def health(conn, _params) do
    ok(conn, %{status: "ok", service: "treedx-api", dataDir: "redacted"})
  end

  def version(conn, _params) do
    ok(conn, %{
      service: "treedx",
      version: TreeDx.Version.version(),
      apiVersion: TreeDx.Version.api_version()
    })
  end

  def ready(conn, _params) do
    readiness = TreeDx.Observability.Health.readiness()

    if readiness.status == "ready" do
      ok(conn, %{readiness: readiness})
    else
      service_unavailable(conn, "Service is not ready.", %{readiness: public_failure(readiness)})
    end
  end

  def deep(conn, _params) do
    health = TreeDx.Observability.Health.deep(detailed: false)

    if health.status in ["healthy", "degraded"] do
      ok(conn, %{health: health})
    else
      service_unavailable(conn, "Service health check failed.", %{health: public_failure(health)})
    end
  end

  def admin_deep(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read") do
      health = TreeDx.Observability.Health.deep(detailed: true)

      if health.status in ["healthy", "degraded"] do
        ok(conn, %{health: health})
      else
        service_unavailable(conn, "Service health check failed.", %{health: health})
      end
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp service_unavailable(conn, message, details) do
    error(conn, 503, %{code: "service_unavailable", message: message, details: details})
  end

  defp public_failure(result) do
    %{
      status: result.status,
      failedChecks:
        result.checks
        |> Enum.filter(&(&1.status == "failed"))
        |> Enum.map(& &1.name)
    }
  end
end
