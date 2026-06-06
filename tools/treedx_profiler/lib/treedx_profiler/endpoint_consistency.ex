defmodule TreeDxProfiler.EndpointConsistency do
  @moduledoc false

  @checks [
    {"repo_path_list_to_read", ["listRepositoryPaths", "readRepositoryFile"]},
    {"workspace_status_to_diff", ["getWorkspaceStatus", "getWorkspaceDiff"]},
    {"search_to_read", ["searchRepositoryFiles", "readRepositoryFile"]},
    {"query_to_read", ["queryRepository", "readRepositoryFile"]},
    {"graph_to_context", ["queryRepositoryGraph", "buildContext"]},
    {"snapshot_to_artifact", ["buildSnapshot", "exportArtifact"]},
    {"artifact_list_to_show", ["listArtifacts", "getArtifact"]},
    {"metrics_after_operations", ["getMetrics"]}
  ]

  def report(samples, _state, _opts) do
    ids = samples |> Enum.map(& &1.operation_id) |> MapSet.new()

    results =
      Enum.map(@checks, fn {name, required} ->
        missing = Enum.reject(required, &MapSet.member?(ids, &1))
        %{"name" => name, "passed" => missing == [], "missing" => missing}
      end)

    failures = Enum.reject(results, & &1["passed"])

    %{
      "total" => length(results),
      "passed" => length(results) - length(failures),
      "failed" => length(failures),
      "failures" => failures
    }
  end
end
