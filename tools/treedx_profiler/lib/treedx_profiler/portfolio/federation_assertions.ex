defmodule TreeDxProfiler.FederationAssertions do
  @moduledoc false

  def assertion(name, passed?, message \\ nil) do
    %{
      operation_id: "federationTopology",
      rule: name,
      passed: passed?,
      status: if(passed?, do: "passed", else: "failed"),
      message: message
    }
  end
end
