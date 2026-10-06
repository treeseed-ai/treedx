defmodule TreeDxProfiler.RestartDurability do
  @moduledoc false

  def report(opts) do
    %{
      "enabled" => opts.restart_durability_check,
      "restarts" => 0,
      "readinessRecovered" => if(opts.restart_durability_check, do: nil, else: true),
      "reconciliationAfterRestart" => %{"passed" => not opts.restart_durability_check},
      "status" =>
        if(opts.restart_durability_check, do: "requires compose control", else: "disabled")
    }
  end
end
