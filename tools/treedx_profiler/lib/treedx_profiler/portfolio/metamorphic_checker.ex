defmodule TreeDxProfiler.MetamorphicChecker do
  @moduledoc false

  def report(samples, opts) do
    checks =
      [
        {"query_stability", ["queryRepository"]},
        {"snapshot_stability", ["buildSnapshot", "getSnapshot"]},
        {"path_list_read_consistency", ["listRepositoryPaths", "readRepositoryFile"]},
        {"search_result_read_consistency", ["searchRepositoryFiles", "readRepositoryFile"]},
        {"artifact_list_show_consistency", ["listArtifacts", "getArtifact"]},
        {"workspace_status_diff_consistency", ["getWorkspaceStatus", "getWorkspaceDiff"]}
      ]

    sample_ids = samples |> Enum.map(& &1.operation_id) |> MapSet.new()

    results =
      if opts.metamorphic_checks do
        Enum.map(checks, fn {name, required} ->
          missing = Enum.reject(required, &MapSet.member?(sample_ids, &1))
          %{"name" => name, "passed" => missing == [], "missing" => missing}
        end)
      else
        []
      end

    failures = Enum.reject(results, & &1["passed"])

    %{
      "enabled" => opts.metamorphic_checks,
      "total" => length(results),
      "passed" => length(results) - length(failures),
      "failed" => length(failures),
      "failures" => failures
    }
  end
end
