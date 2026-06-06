defmodule TreeDxProfiler.OpenApiResponseValidatorTest do
  use ExUnit.Case, async: true

  alias TreeDxProfiler.OpenApiResponseValidator

  test "validates documented operations and statuses" do
    assert :ok =
             OpenApiResponseValidator.validate_response("getHealth", 200, %{
               "ok" => true,
               "health" => %{"status" => "ok"}
             })
  end

  test "rejects undocumented operation" do
    assert {:error, message} =
             OpenApiResponseValidator.validate_response("missingOperation", 200, %{"ok" => true})

    assert message =~ "not found"
  end

  test "summarizes response validation failures" do
    report =
      OpenApiResponseValidator.report([
        %{openapiValidation: %{operationId: "getHealth", status: 200, passed: true}},
        %{
          openapiValidation: %{
            operationId: "missingOperation",
            status: 200,
            passed: false,
            message: "missing"
          }
        }
      ])

    assert report["totalResponses"] == 2
    assert report["failed"] == 1
  end
end
