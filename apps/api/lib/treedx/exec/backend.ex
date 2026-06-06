defmodule TreeDx.Exec.Backend do
  @moduledoc false

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    with {:ok, module} <- backend_module(),
         :ok <- validate_runtime(module) do
      module.run(command, cwd, timeout_ms, max_output_bytes, opts)
    end
  end

  def backend_name do
    System.get_env("TREEDX_EXEC_BACKEND") || "direct_dev"
  end

  def resource_limits(params \\ %{}) do
    requested = params["resourceLimits"] || %{}

    %{
      cpu: min_number(requested["cpu"], env_number("TREEDX_EXEC_MAX_CPU", 1)),
      memoryMb: min_number(requested["memoryMb"], env_number("TREEDX_EXEC_MAX_MEMORY_MB", 512)),
      pids: min_number(requested["pids"], env_number("TREEDX_EXEC_MAX_PIDS", 64))
    }
  end

  def network(params \\ %{}) do
    requested = params["network"] || System.get_env("TREEDX_EXEC_NETWORK_DEFAULT") || "none"

    if requested == "none" do
      {:ok, "none"}
    else
      {:error, %{code: "sandbox_policy_denied", message: "Exec network access is disabled."}}
    end
  end

  defp backend_module do
    case backend_name() do
      "direct_dev" ->
        {:ok, TreeDx.Exec.Backends.DirectDev}

      "container_sandbox" ->
        {:ok, TreeDx.Exec.Backends.ContainerSandbox}

      "external_worker" ->
        {:ok, TreeDx.Exec.Backends.ExternalWorker}

      "firecracker_or_microvm" ->
        {:ok, TreeDx.Exec.Backends.FirecrackerMicrovm}

      other ->
        {:error, %{code: "validation_error", message: "Unknown exec backend #{other}."}}
    end
  end

  defp validate_runtime(TreeDx.Exec.Backends.DirectDev) do
    production? = TreeDx.Auth.mode() == "connected" or System.get_env("MIX_ENV") == "prod"

    if production? and System.get_env("TREEDX_ALLOW_DIRECT_EXEC_IN_PROD") != "true" do
      {:error,
       %{
         code: "sandbox_policy_denied",
         message: "direct_dev exec backend is disabled in connected/prod mode."
       }}
    else
      :ok
    end
  end

  defp validate_runtime(_module), do: :ok

  defp env_number(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} -> value
      _ -> default
    end
  end

  defp min_number(nil, max), do: max
  defp min_number(value, max) when is_integer(value), do: min(value, max)
  defp min_number(value, max) when is_float(value), do: min(value, max)

  defp min_number(value, max) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> min(number, max)
      _ -> max
    end
  end

  defp min_number(_value, max), do: max
end
