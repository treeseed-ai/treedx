defmodule TreeDxSdk.Generated.OpenApiTypesTest do
  use ExUnit.Case, async: true

  test "operation count matches OpenAPI baseline" do
    assert TreeDxSdk.Generated.OpenApiTypes.operation_count() == 118
    assert length(TreeDxSdk.Generated.OpenApiTypes.operations()) == 118
  end
end
