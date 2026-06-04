defmodule TreeDbProfiler.ScenarioDefinitionTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.Scenario

  test "every scenario definition loads and has valid positive weights" do
    assert :ok = Scenario.validate!()

    for id <- Scenario.all() do
      scenario = Scenario.load(id)
      assert scenario["id"] == id
      assert is_list(get_in(scenario, ["operationSelection", "includeTags"]))
      assert is_list(get_in(scenario, ["operationSelection", "excludeTags"]))

      for {_operation, weight} <- scenario["weights"] || %{} do
        assert is_integer(weight)
        assert weight > 0
      end
    end
  end

  test "all scenario expands to all scenario definitions" do
    assert Scenario.load("all") |> length() == length(Scenario.all())
  end
end
