defmodule TreeDxProfiler.PermissionMatrix do
  @moduledoc false

  def report(samples, opts) do
    if opts.permission_matrix do
      authz_samples =
        Enum.filter(samples, fn sample ->
          permission_sample?(sample, opts)
        end)

      failures =
        Enum.filter(authz_samples, fn sample ->
          sample.status in [401, 403] and
            sample.error_code not in ["permission_denied", "unauthorized"]
        end)

      %{
        "enabled" => true,
        "total" => length(authz_samples),
        "passed" => length(authz_samples) - length(failures),
        "failed" => length(failures),
        "actors" => %{
          "admin_actor" => %{
            "passed" => length(authz_samples) - length(failures),
            "failed" => length(failures)
          },
          "unauthorized_actor" => %{"passed" => 0, "failed" => 0}
        },
        "failures" =>
          Enum.map(
            failures,
            &%{
              "operationId" => &1.operation_id,
              "status" => &1.status,
              "errorCode" => &1.error_code
            }
          )
      }
    else
      %{"enabled" => false, "total" => 0, "passed" => 0, "failed" => 0, "actors" => %{}}
    end
  end

  defp permission_sample?(%{category: category}, _opts) when category in ["policy", "auth"],
    do: true

  defp permission_sample?(%{operation_id: "execWorkspace"}, %{include_exec: false}), do: false

  defp permission_sample?(%{status: status}, _opts), do: status in [401, 403]
end
