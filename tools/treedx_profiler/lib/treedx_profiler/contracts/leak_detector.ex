defmodule TreeDxProfiler.LeakDetector do
  @moduledoc false

  def report(state) do
    before_metrics = state[:metrics_before] || %{}
    after_metrics = state[:metrics_after] || %{}
    active_workspaces = get_in(state, [:portfolio, "activeWorkspaces"]) || 0
    portfolio_mode? = state.opts.load_mode == "portfolio"

    warnings =
      []
      |> maybe_warn(
        active_workspaces > 0 and state.opts.cleanup and not portfolio_mode?,
        "active workspaces remained after cleanup"
      )

    %{
      "expectedRetainedWorkspaces" => if(portfolio_mode?, do: active_workspaces, else: 0),
      "samples" => Enum.count([before_metrics, after_metrics], &(&1 != %{})),
      "warnings" => warnings,
      "failures" => []
    }
  end

  defp maybe_warn(warnings, true, message), do: [%{"message" => message} | warnings]
  defp maybe_warn(warnings, false, _message), do: warnings
end
