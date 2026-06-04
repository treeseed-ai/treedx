defmodule TreeDbProfiler.EndpointMatrixTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.{EndpointMatrix, Scenario, Validation}

  test "endpoint matrix accounts for every OpenAPI operation" do
    assert :ok = EndpointMatrix.validate!()
    matrix = EndpointMatrix.load()
    openapi = EndpointMatrix.openapi_operations()

    assert length(matrix) == length(openapi)
    assert length(matrix) > 0
  end

  test "every matrix entry has required fields and known validation rule" do
    scenario_ids = ["full_api" | Scenario.all()]

    for operation <- EndpointMatrix.load() do
      assert is_binary(operation["operationId"])
      assert operation["method"] in ["GET", "POST", "PUT", "PATCH", "DELETE"]
      assert is_binary(operation["path"])
      assert is_list(operation["tags"])
      assert is_map(operation["setup"])
      assert is_list(operation["expectedStatus"])
      assert get_in(operation, ["validation", "rule"]) in Validation.rules()

      assert operation["scenarios"]
             |> Map.keys()
             |> Enum.all?(&(&1 in scenario_ids))
    end
  end

  test "full_api has no unaccounted operations" do
    opts = %{
      scenario: "full_api",
      include_admin: false,
      include_destructive: false,
      include_exec: false,
      include_federation: false
    }

    assert EndpointMatrix.coverage([], opts)["unaccounted"] == 0
  end
end
