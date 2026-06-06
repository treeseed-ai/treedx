defmodule TreeDxSdk.ConformanceTest do
  use ExUnit.Case, async: true

  defp scenarios do
    "../sdk-spec/conformance/scenarios"
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".yaml"))
    |> Enum.flat_map(fn file ->
      text = File.read!(Path.join("../sdk-spec/conformance/scenarios", file))
      ids = Regex.scan(~r/^  - id: (.+)$/m, text) |> Enum.map(fn [_, id] -> id end)
      caps = Regex.scan(~r/^    capabilityId: (.+)$/m, text) |> Enum.map(fn [_, id] -> id end)
      Enum.zip(ids, caps) |> Enum.map(fn {id, cap} -> %{"id" => id, "capabilityId" => cap} end)
    end)
  end

  test "scenario catalog loads and reports not configured" do
    client = TreeDxSdk.Client.new(base_url: "http://localhost:4000")
    adapter = TreeDxSdk.Conformance.Adapter.new(client)
    scenarios = scenarios()
    assert scenarios != []

    for scenario <- scenarios do
      assert scenario["id"] != ""
      assert scenario["capabilityId"] != ""

      assert %{status: :not_configured} =
               TreeDxSdk.Conformance.Adapter.run_scenario(adapter, scenario)
    end
  end
end
