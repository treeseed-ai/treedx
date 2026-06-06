defmodule TreeDxSdk.Generated.OpenApiFreshnessTest do
  use ExUnit.Case, async: true

  test "generated metadata is fresh" do
    {output, status} =
      System.cmd("mix", ["run", "scripts/check_treedx_generated_types.exs"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "generated operations include sdk-spec declared endpoints" do
    generated =
      MapSet.new(
        Enum.map(TreeDxSdk.Generated.OpenApiTypes.operations(), &(&1.method <> " " <> &1.path))
      )

    endpoints =
      "../sdk-spec/spec/endpoints.yaml"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&(String.trim(&1) |> String.starts_with?("- ")))
      |> Enum.map(&(String.trim(&1) |> String.trim_leading("- ")))
      |> Enum.filter(&String.contains?(&1, "/api/v1/"))

    for endpoint <- endpoints do
      assert MapSet.member?(generated, endpoint), "missing #{endpoint}"
    end
  end
end
