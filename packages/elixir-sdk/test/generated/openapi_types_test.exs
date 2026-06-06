defmodule TreeDxSdk.Generated.OpenApiTypesTest do
  use ExUnit.Case, async: true

  test "operation count matches OpenAPI baseline" do
    assert TreeDxSdk.Generated.OpenApiTypes.operation_count() == 113
    assert length(TreeDxSdk.Generated.OpenApiTypes.operations()) == 113
  end
end
