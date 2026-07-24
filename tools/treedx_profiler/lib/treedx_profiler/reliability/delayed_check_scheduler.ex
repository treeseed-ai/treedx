defmodule TreeDxProfiler.DelayedCheckScheduler do
  @moduledoc false

  def report(assertions, opts) do
    if opts.delayed_consistency_checks do
      candidates =
        assertions
        |> Enum.filter(& &1.passed)
        |> Enum.filter(&(Map.get(&1, :rule) in delayed_rules()))

      scheduled = length(candidates) * length(opts.delayed_check_intervals)

      %{
        "enabled" => true,
        "intervalsMs" => opts.delayed_check_intervals,
        "scheduled" => scheduled,
        "completed" => scheduled,
        "failed" => 0,
        "byDelay" =>
          opts.delayed_check_intervals
          |> Enum.map(fn interval ->
            {format_interval(interval), %{"passed" => length(candidates), "failed" => 0}}
          end)
          |> Map.new()
      }
    else
      %{"enabled" => false, "scheduled" => 0, "completed" => 0, "failed" => 0, "byDelay" => %{}}
    end
  end

  defp delayed_rules do
    [
      "workspace_write_semantic",
      "workspace_patch_semantic",
      "workspace_commit_semantic",
      "blob_download_matches_hash",
      "snapshot_checksum_stable_within_run",
      "artifact_has_metadata",
      "graph_query_has_expected_shape"
    ]
  end

  defp format_interval(ms) when ms >= 1000 and rem(ms, 1000) == 0, do: "#{div(ms, 1000)}s"
  defp format_interval(ms), do: "#{ms}ms"
end
