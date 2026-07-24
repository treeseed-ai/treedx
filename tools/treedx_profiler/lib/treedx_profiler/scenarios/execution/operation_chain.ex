defmodule TreeDxProfiler.OperationChain do
  @moduledoc false

  @chains %{
    "workspace_write_commit_search" => [
      "createWorkspace",
      "writeWorkspaceFile",
      "readWorkspaceFile",
      "getWorkspaceStatus",
      "getWorkspaceDiff",
      "commitWorkspace",
      "searchRepositoryFiles",
      "queryRepository"
    ],
    "blob_lifecycle" => [
      "writeWorkspaceBlob",
      "downloadWorkspaceBlob",
      "deleteWorkspaceBlob"
    ],
    "snapshot_artifact_lifecycle" => [
      "buildSnapshot",
      "getSnapshot",
      "exportArtifact",
      "listArtifacts",
      "getArtifact"
    ],
    "graph_context" => [
      "refreshRepositoryGraph",
      "getGraphRefreshJob",
      "queryRepositoryGraph",
      "searchGraphFiles",
      "searchGraphSections",
      "searchGraphEntities",
      "buildContext"
    ]
  }

  def report(samples, opts) do
    sample_ids = samples |> Enum.map(& &1.operation_id) |> MapSet.new()

    by_chain =
      @chains
      |> Enum.map(fn {name, operations} ->
        missing = Enum.reject(operations, &MapSet.member?(sample_ids, &1))
        passed? = missing == [] or not opts.operation_chains

        {name,
         %{
           "passed" => if(passed?, do: 1, else: 0),
           "failed" => if(passed?, do: 0, else: 1),
           "missing" => missing
         }}
      end)
      |> Map.new()

    failed = Enum.count(by_chain, fn {_name, chain} -> chain["failed"] > 0 end)

    %{
      "enabled" => opts.operation_chains,
      "total" => map_size(by_chain),
      "passed" => map_size(by_chain) - failed,
      "failed" => failed,
      "byChain" => by_chain
    }
  end
end
