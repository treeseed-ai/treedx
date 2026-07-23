defmodule TreeDx.RepositoryQuery.Context do
  @moduledoc false

  def resolve(_repo_id, %{"__ctx" => ctx}, _principal, _capability), do: {:ok, ctx}

  def resolve(repo_id, params, principal, capability) do
    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, capability, repo_id),
         {:ok, repo} when is_map(repo) <- repository(repo_id),
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

  defp repository(repo_id) do
    case TreeDx.Store.get_repository(repo_id) do
      {:ok, repo} when is_map(repo) -> {:ok, repo}
      _ -> mirror_repository(repo_id)
    end
  end

  defp mirror_repository(repo_id) do
    local_node = TreeDx.Federation.NodeIdentity.node_id()

    with {:ok, route} when is_map(route) <- TreeDx.Store.get_federation_route(repo_id),
         true <- local_node in (route["mirrorNodeIds"] || []),
         repository_name when is_binary(repository_name) and repository_name != "" <-
           route["repositoryName"] do
      {:ok,
       %{
         "id" => repo_id,
         "repositoryName" => repository_name,
         "defaultRef" => route["defaultRef"] || "refs/heads/main",
         "storageKind" => "mirror",
         "storageRelativePath" => TreeDx.RepositoryStorage.mirror_relative_path(repository_name)
       }}
    else
      _ -> {:ok, nil}
    end
  end
end
