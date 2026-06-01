defmodule TreeDb.Workspaces do
  @moduledoc false

  def create(repo_id, params, principal) do
    mode = normalize_mode(params["mode"] || "read_only")
    base_ref = params["baseRef"] || "refs/heads/main"
    branch_name = params["branchName"]
    allowed_paths = params["allowedPaths"] || ["**"]
    ttl = params["ttlSeconds"] || 1800
    local_node_id = System.get_env("TREEDB_NODE_ID") || "node_local"

    required_repo_capability = if mode == "writable", do: "repos:write", else: "repos:read"

    with {:ok, create_scope} <-
           TreeDb.Capabilities.require_capability(principal, "workspace:create", repo_id),
         {:ok, repo_scope} <-
           TreeDb.Capabilities.require_capability(principal, required_repo_capability, repo_id),
         :ok <- TreeDb.Capabilities.require_ref(repo_scope, base_ref),
         :ok <- require_branch_scope(repo_scope, branch_name),
         :ok <- TreeDb.Capabilities.require_paths(repo_scope, allowed_paths),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         {:ok, placement} when is_map(placement) <-
           TreeDb.Store.get_repository_placement(repo_id),
         :ok <- ensure_placement_allows(mode, placement, local_node_id),
         {:ok, workspace} <-
           persist_workspace(repo, placement, principal, create_scope, %{
             mode: mode,
             base_ref: base_ref,
             branch_name: branch_name,
             allowed_paths: allowed_paths,
             ttl: ttl
           }) do
      TreeDb.Audit.append("workspace.created", %{
        actor_id: actor_id(principal),
        tenant_id: tenant_id(principal),
        repo_id: repo_id,
        data: %{workspaceId: workspace["id"], mode: mode, baseRef: base_ref}
      })

      {:ok, public_workspace(workspace)}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def get(workspace_id, principal) do
    with {:ok, workspace} when is_map(workspace) <- TreeDb.Store.get_workspace(workspace_id),
         :ok <- workspace_actor_allowed(workspace, principal) do
      {:ok, public_workspace(workspace)}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      other -> other
    end
  end

  def close(workspace_id, principal) do
    with {:ok, workspace} when is_map(workspace) <- TreeDb.Store.get_workspace(workspace_id),
         :ok <- workspace_actor_allowed(workspace, principal),
         {:ok, closed} when is_map(closed) <- TreeDb.Store.close_workspace(workspace_id) do
      TreeDb.Audit.append("workspace.closed", %{
        actor_id: actor_id(principal),
        tenant_id: tenant_id(principal),
        repo_id: closed["repositoryId"],
        data: %{workspaceId: workspace_id}
      })

      {:ok, public_workspace(closed)}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      other -> other
    end
  end

  def cleanup_expired do
    TreeDb.Store.cleanup_expired_workspaces()
  end

  defp persist_workspace(repo, placement, principal, scope, opts) do
    workspace_id = TreeDb.Ids.workspace()
    materialized_path = Path.join([TreeDb.Store.data_dir(), "workspaces", "active", workspace_id])
    File.mkdir_p!(materialized_path)

    input = %{
      id: workspace_id,
      repositoryId: repo["id"],
      nodeId: placement["primaryNodeId"],
      actorId: actor_id(principal),
      tenantId: tenant_id(principal),
      baseRef: opts.base_ref,
      branchName: opts.branch_name,
      mode: opts.mode,
      allowedPaths: opts.allowed_paths,
      capabilities: workspace_capabilities(opts.mode),
      ttlSeconds: opts.ttl,
      materializedPath: materialized_path,
      effectiveScope: %{
        actorId: scope["actorId"],
        tenantId: scope["tenantId"],
        repoIds: [repo["id"]],
        capabilities: workspace_capabilities(opts.mode),
        refs: workspace_refs(scope, opts),
        paths: opts.allowed_paths
      }
    }

    TreeDb.Store.put_workspace(input)
  end

  defp normalize_mode("writable"), do: "writable"
  defp normalize_mode("read_only"), do: "read_only"
  defp normalize_mode("read-only"), do: "read_only"
  defp normalize_mode(_), do: "read_only"

  defp require_branch_scope(_scope, nil), do: :ok

  defp require_branch_scope(scope, branch_name),
    do: TreeDb.Capabilities.require_ref(scope, branch_name)

  defp ensure_placement_allows("writable", placement, local_node_id) do
    if placement["primaryNodeId"] == local_node_id do
      :ok
    else
      {:error,
       %{
         code: "permission_denied",
         message: "Writable workspaces must be created on the primary node."
       }}
    end
  end

  defp ensure_placement_allows(_mode, _placement, _local_node_id), do: :ok

  defp workspace_actor_allowed(workspace, principal) do
    if workspace["actorId"] == actor_id(principal) do
      :ok
    else
      {:error, %{code: "permission_denied", message: "Permission denied."}}
    end
  end

  defp workspace_capabilities("writable") do
    [
      "files:read",
      "files:write",
      "files:search",
      "workspace:exec:read_only",
      "git:diff",
      "git:commit"
    ]
  end

  defp workspace_capabilities(_),
    do: ["files:read", "files:search", "workspace:exec:read_only", "git:diff"]

  defp workspace_refs(_scope, %{branch_name: branch_name}) when is_binary(branch_name),
    do: [branch_name]

  defp workspace_refs(scope, _opts), do: scope["refs"] || []

  defp actor_id(principal),
    do: principal["actorId"] || principal[:actorId] || principal[:actor_id]

  defp tenant_id(principal),
    do: principal["tenantId"] || principal[:tenantId] || principal[:tenant_id]

  defp public_workspace(workspace) do
    %{
      workspaceId: workspace["id"],
      repoId: workspace["repositoryId"],
      nodeId: workspace["nodeId"],
      baseRef: workspace["baseRef"],
      branchName: workspace["branchName"],
      mode: workspace["mode"],
      status: workspace["status"],
      expiresAt: workspace["expiresAt"],
      materializedPath: workspace["materializedPath"],
      effectiveScope: workspace["effectiveScope"],
      capabilities: workspace["capabilities"]
    }
  end
end
