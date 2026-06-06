defmodule TreeDxProfiler.FaultInjection do
  @moduledoc false

  def report(opts) do
    %{
      "enabled" => opts.fault_injection,
      "injected" => 0,
      "recovered" => 0,
      "failures" => [],
      "status" =>
        if(opts.fault_injection, do: "available but no faults configured", else: "disabled")
    }
  end
end
