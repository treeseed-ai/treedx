defmodule TreeDxProfiler.PortfolioNormalization do
  @moduledoc false

  def normalize(repo, index, now) do
    files = repo[:files] || []

    %{
      index: index,
      name: repo.name,
      path: repo.path,
      repo_id: repo[:repo_id],
      generation: repo[:generation] || 0,
      created_at_ms: now,
      deleted?: false,
      created_by_request_id: repo[:created_by_request_id],
      deleted_by_request_id: nil,
      committed_paths: %{},
      default_ref: repo[:default_ref] || "refs/heads/main",
      readable_paths:
        files
        |> Enum.filter(
          &(&1.kind in ["markdown", "text", "json", "workspace_write", "workspace_patch"])
        )
        |> Enum.map(&%{path: &1.path, sha256: &1.sha256, content: &1[:content]}),
      binary_paths:
        files
        |> Enum.filter(&(&1.kind == "binary"))
        |> Enum.map(&%{path: &1.path, sha256: &1.sha256, byte_length: &1.byte_length})
    }
  end
end
