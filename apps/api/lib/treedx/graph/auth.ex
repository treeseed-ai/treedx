defmodule TreeDx.Graph.Auth do
  @moduledoc false

  def context(repo_id, params, principal, capability) do
    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, capability, repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         :ok <- TreeDx.Capabilities.require_ref(scope, ref),
         {:ok, resolved} <- TreeDx.Git.resolve_ref(TreeDx.RepositoryStorage.path!(repo), ref) do
      {:ok,
       %{
         repo: repo,
         ref: ref,
         resolved_ref: resolved["target"],
         scope: scope,
         principal: principal
       }}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end
end
