defmodule TreeDxSdk.Conformance.Adapter do
  @moduledoc false
  defstruct [:client, server_configured: false]

  def new(client, opts \\ []),
    do: %__MODULE__{
      client: client,
      server_configured: Keyword.get(opts, :server_configured, false)
    }

  def run_scenario(%__MODULE__{server_configured: false}, scenario) do
    %{
      scenario_id: scenario["id"],
      status: :not_configured,
      message: "TreeDX server is not configured"
    }
  end

  def run_scenario(%__MODULE__{client: client, server_configured: true}, scenario) do
    path_params = %{
      "repo_id" => env_or("TREEDX_CONFORMANCE_REPO_ID", "repo_conformance"),
      "workspace_id" => env_or("TREEDX_CONFORMANCE_WORKSPACE_ID", "workspace_conformance"),
      "node_id" => env_or("TREEDX_CONFORMANCE_NODE_ID", "node_conformance"),
      "job_id" => env_or("TREEDX_CONFORMANCE_JOB_ID", "job_conformance"),
      "snapshot_id" => env_or("TREEDX_CONFORMANCE_SNAPSHOT_ID", "snapshot_conformance"),
      "artifact_id" => env_or("TREEDX_CONFORMANCE_ARTIFACT_ID", "artifact_conformance"),
      "mirror_id" => env_or("TREEDX_CONFORMANCE_MIRROR_ID", "mirror_conformance"),
      "migration_id" => env_or("TREEDX_CONFORMANCE_MIGRATION_ID", "migration_conformance"),
      "upload_id" => env_or("TREEDX_CONFORMANCE_UPLOAD_ID", "upload_conformance"),
      "part_number" => env_or("TREEDX_CONFORMANCE_PART_NUMBER", "1")
    }

    result =
      Enum.reduce_while(Map.get(scenario, "endpointRefs", []), :ok, fn endpoint_ref, :ok ->
        [method, path] = String.split(endpoint_ref, " ", parts: 2)
        body = if method in ["GET", "DELETE"], do: nil, else: %{planOnly: true}

        case TreeDxSdk.Client.operation(client, method, path,
               path_params: path_params,
               body: body
             ) do
          {:ok, _value} -> {:cont, :ok}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)

    case result do
      :ok ->
        %{scenario_id: scenario["id"], status: :passed, message: nil}

      {:error, error} ->
        %{scenario_id: scenario["id"], status: :failed, message: Exception.message(error)}
    end
  end

  defp env_or(name, fallback), do: System.get_env(name) || fallback
end
