defmodule TreeDbProfiler.Scenario do
  @moduledoc false

  @scenarios ["full_api", "read_heavy", "write_heavy", "graph_context", "blob_artifact"]

  def all, do: @scenarios

  def load("all"), do: Enum.map(@scenarios, &load/1)

  def load(id) when id in @scenarios do
    id
    |> path!()
    |> File.read!()
    |> Jason.decode!()
  end

  def load(id), do: raise("unknown scenario #{inspect(id)}")

  def validate! do
    Enum.each(@scenarios, fn id ->
      scenario = load(id)
      weights = scenario["weights"] || %{}

      unless is_map(get_in(scenario, ["operationSelection"])) do
        raise "scenario #{id} missing operationSelection"
      end

      Enum.each(weights, fn {operation_id, weight} ->
        unless is_integer(weight) and weight > 0 do
          raise "scenario #{id} has invalid weight for #{operation_id}"
        end
      end)
    end)

    :ok
  end

  defp path!(id), do: Path.expand("../../scenarios/#{id}.yaml", __DIR__)
end
