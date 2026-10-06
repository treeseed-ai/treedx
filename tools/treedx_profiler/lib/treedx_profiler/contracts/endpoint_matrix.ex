defmodule TreeDxProfiler.EndpointMatrix do
  @moduledoc false

  alias TreeDxProfiler.Scenario

  @required_fields [
    "operationId",
    "method",
    "path",
    "tags",
    "operationType",
    "category",
    "randomizable",
    "mutability",
    "idempotency",
    "concurrencyMode",
    "setup",
    "expectedStatus",
    "validation",
    "scenarios"
  ]

  def load do
    matrix_path = path()
    stat = File.stat!(matrix_path)
    key = {__MODULE__, matrix_path, stat.mtime, stat.size}

    case :persistent_term.get(key, :missing) do
      :missing ->
        operations =
          matrix_path
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("operations")
          |> Enum.map(&with_runtime_defaults/1)

        :persistent_term.put(key, operations)
        operations

      operations ->
        operations
    end
  end

  def operation_map do
    matrix_path = path()
    stat = File.stat!(matrix_path)
    key = {__MODULE__, :operation_map, matrix_path, stat.mtime, stat.size}

    case :persistent_term.get(key, :missing) do
      :missing ->
        indexed = load() |> Map.new(&{&1["operationId"], &1})
        :persistent_term.put(key, indexed)
        indexed

      indexed ->
        indexed
    end
  end

  def validate! do
    operations = load()
    matrix_ids = operations |> Enum.map(& &1["operationId"]) |> MapSet.new()
    openapi_ids = openapi_operations() |> Enum.map(& &1.operation_id) |> MapSet.new()

    missing = MapSet.difference(openapi_ids, matrix_ids) |> MapSet.to_list() |> Enum.sort()
    extra = MapSet.difference(matrix_ids, openapi_ids) |> MapSet.to_list() |> Enum.sort()

    invalid =
      Enum.flat_map(operations, fn operation ->
        missing_fields =
          @required_fields
          |> Enum.reject(&Map.has_key?(operation, &1))
          |> Enum.map(&"#{operation["operationId"] || "unknown"} missing #{&1}")

        missing_fields ++ validation_errors(operation)
      end)

    case {missing, extra, invalid} do
      {[], [], []} ->
        :ok

      _ ->
        raise "endpoint matrix drift: #{inspect(%{missing: missing, extra: extra, invalid: invalid})}"
    end
  end

  def openapi_operations do
    TreeDxProfiler.OpenApiSpec.load!()
    |> Map.fetch!("paths")
    |> Enum.flat_map(fn {path, methods} ->
      Enum.flat_map(methods, fn {method, operation} ->
        if is_map(operation) and operation["operationId"] do
          [%{operation_id: operation["operationId"], method: String.upcase(method), path: path}]
        else
          []
        end
      end)
    end)
  end

  def select(scenario, opts) do
    weights = scenario_weights(scenario)

    load()
    |> Enum.filter(&selected_by_scenario?(&1, scenario, weights))
    |> Enum.filter(&enabled?(&1, opts))
    |> Enum.flat_map(fn operation ->
      weight = weights[operation["operationId"]] || matrix_weight(operation, scenario)

      List.duplicate(operation, weight)
    end)
  end

  def coverage(samples, opts, extra_operation_ids \\ []) do
    sample_ids =
      samples
      |> Enum.map(& &1.operation_id)
      |> Kernel.++(List.wrap(extra_operation_ids))
      |> MapSet.new()

    openapi_ids = openapi_operations() |> Enum.map(& &1.operation_id) |> MapSet.new()
    matrix = load()
    matrix_ids = matrix |> Enum.map(& &1["operationId"]) |> MapSet.new()

    operation_statuses =
      Enum.map(matrix, fn operation ->
        id = operation["operationId"]
        status = coverage_status(operation, sample_ids, opts)
        %{"operationId" => id, "status" => status, "reason" => coverage_reason(status, opts)}
      end)

    unaccounted = MapSet.difference(openapi_ids, matrix_ids) |> MapSet.to_list() |> Enum.sort()

    %{
      "openapiOperations" => MapSet.size(openapi_ids),
      "matrixOperations" => MapSet.size(matrix_ids),
      "exercised" => Enum.count(operation_statuses, &(&1["status"] == "exercised")),
      "adminDisabled" => Enum.count(operation_statuses, &(&1["status"] == "admin_disabled")),
      "destructiveDisabled" =>
        Enum.count(operation_statuses, &(&1["status"] == "destructive_disabled")),
      "execDisabled" => Enum.count(operation_statuses, &(&1["status"] == "exec_disabled")),
      "federationDisabled" =>
        Enum.count(operation_statuses, &(&1["status"] == "federation_disabled")),
      "optionalUnavailable" =>
        Enum.count(operation_statuses, &(&1["status"] == "optional_unavailable")),
      "notSelectedByScenario" =>
        Enum.count(operation_statuses, &(&1["status"] == "not_selected_by_scenario")),
      "unaccounted" => length(unaccounted),
      "unaccountedOperations" => unaccounted,
      "operations" => operation_statuses
    }
  end

  def scenario_ids("all"),
    do: ["full_api", "read_heavy", "write_heavy", "graph_context", "blob_artifact"]

  def scenario_ids(scenario), do: [scenario]

  defp enabled?(operation, opts) do
    tags = MapSet.new(operation["tags"] || [])

    cond do
      MapSet.member?(tags, "admin") and not opts.include_admin -> false
      MapSet.member?(tags, "destructive") and not opts.include_destructive -> false
      MapSet.member?(tags, "exec") and not opts.include_exec -> false
      MapSet.member?(tags, "federation") and not opts.include_federation -> false
      true -> true
    end
  end

  defp coverage_status(operation, sample_ids, opts) do
    tags = MapSet.new(operation["tags"] || [])
    id = operation["operationId"]

    selected? = selected_by_scenario?(operation, opts.scenario, scenario_weights(opts.scenario))

    cond do
      MapSet.member?(sample_ids, id) ->
        "exercised"

      MapSet.member?(tags, "admin") and not opts.include_admin ->
        "admin_disabled"

      MapSet.member?(tags, "destructive") and not opts.include_destructive ->
        "destructive_disabled"

      MapSet.member?(tags, "exec") and not opts.include_exec ->
        "exec_disabled"

      MapSet.member?(tags, "federation") and not opts.include_federation ->
        "federation_disabled"

      selected? ->
        "optional_unavailable"

      true ->
        "not_selected_by_scenario"
    end
  end

  defp coverage_reason("admin_disabled", _), do: "includeAdmin=false"
  defp coverage_reason("destructive_disabled", _), do: "includeDestructive=false"
  defp coverage_reason("exec_disabled", _), do: "includeExec=false"
  defp coverage_reason("federation_disabled", _), do: "includeFederation=false"

  defp coverage_reason("optional_unavailable", _),
    do: "missing setup state or unsupported target configuration"

  defp coverage_reason("not_selected_by_scenario", opts), do: "not selected by #{opts.scenario}"
  defp coverage_reason(_, _), do: nil

  defp scenario_weights(scenario) when scenario in ["all", "full_api"], do: %{}
  defp scenario_weights(scenario), do: Scenario.load(scenario)["weights"] || %{}

  defp selected_by_scenario?(operation, _scenario, weights) when map_size(weights) > 0,
    do: Map.has_key?(weights, operation["operationId"])

  defp selected_by_scenario?(operation, scenario, _weights),
    do: Enum.any?(scenario_ids(scenario), &Map.has_key?(operation["scenarios"] || %{}, &1))

  defp matrix_weight(operation, scenario) do
    scenario
    |> scenario_ids()
    |> Enum.map(&(get_in(operation, ["scenarios", &1, "weight"]) || 0))
    |> Enum.max()
    |> max(1)
  end

  defp validation_errors(operation) do
    scenarios = operation["scenarios"] || %{}

    cond do
      not is_list(operation["tags"]) ->
        ["#{operation["operationId"]} tags must be a list"]

      not is_map(operation["validation"]) ->
        ["#{operation["operationId"]} validation must be a map"]

      map_size(scenarios) == 0 ->
        ["#{operation["operationId"]} must belong to at least one scenario"]

      true ->
        []
    end
  end

  defp with_runtime_defaults(operation) do
    tags = operation["tags"] || []

    operation
    |> Map.put_new("operationType", infer_operation_type(operation, tags))
    |> Map.put_new("category", infer_category(tags))
    |> Map.put_new("randomizable", randomizable?(operation, tags))
    |> Map.put_new("mutability", infer_mutability(operation["method"]))
    |> Map.put_new("idempotency", infer_idempotency(operation["method"]))
    |> Map.put_new("concurrencyMode", infer_concurrency_mode(tags))
    |> Map.put_new("requestGenerator", infer_request_generator(operation["operationId"]))
    |> Map.put_new("stateEffects", infer_state_effects(operation["operationId"]))
  end

  defp infer_operation_type(%{"method" => "GET"}, _tags), do: "read"
  defp infer_operation_type(%{"method" => "DELETE"}, _tags), do: "delete"

  defp infer_operation_type(%{"operationId" => id}, _tags) do
    cond do
      String.contains?(id, ["Search", "Query", "Context"]) -> "query"
      String.contains?(id, ["Create", "Register", "Build", "Export"]) -> "create"
      String.contains?(id, ["Write", "Upload", "Patch", "Put", "Refresh"]) -> "write"
      true -> "update"
    end
  end

  defp infer_category(tags), do: Enum.find(tags, "general", &(&1 not in ["read", "write"]))

  defp randomizable?(operation, tags),
    do: not Enum.any?(tags, &(&1 in ["admin", "destructive"])) and operation["method"] != "DELETE"

  defp infer_mutability("GET"), do: "read_only"
  defp infer_mutability(_), do: "mutating"
  defp infer_idempotency(method) when method in ["GET", "PUT", "DELETE"], do: "idempotent"
  defp infer_idempotency(_), do: "non_idempotent"

  defp infer_concurrency_mode(tags),
    do: if("workspace" in tags or "repository" in tags, do: "shared_state", else: "stateless")

  defp infer_request_generator(operation_id), do: operation_id
  defp infer_state_effects(_operation_id), do: []

  defp path do
    TreeDxProfiler.CLISupport.profiler_root()
    |> Path.join("endpoint_matrix.yaml")
  end
end
