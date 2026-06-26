defmodule TreeDx.Workspaces do
  @moduledoc false

  def create(repo_id, params, principal) do
    mode = normalize_mode(params["mode"] || "read_only")
    base_ref = params["baseRef"] || "refs/heads/main"
    branch_name = normalize_branch_name(params["branchName"])
    allowed_paths = params["allowedPaths"] || ["**"]
    ttl = params["ttlSeconds"] || 1800
    local_node_id = System.get_env("TREEDX_NODE_ID") || "node_local"

    required_repo_capability = if mode == "writable", do: "repos:write", else: "repos:read"

    with {:ok, create_scope} <-
           TreeDx.Capabilities.require_capability(principal, "workspace:create", repo_id),
         {:ok, repo_scope} <-
           TreeDx.Capabilities.require_capability(principal, required_repo_capability, repo_id),
         :ok <- TreeDx.Capabilities.require_ref(repo_scope, base_ref),
         :ok <- require_branch_scope(repo_scope, branch_name),
         :ok <- TreeDx.Capabilities.require_paths(repo_scope, allowed_paths),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         {:ok, base_resolved} <-
           TreeDx.Git.resolve_ref(TreeDx.RepositoryStorage.path!(repo), base_ref),
         :ok <- ensure_branch_start(repo, branch_name, base_resolved["target"]),
         {:ok, placement} when is_map(placement) <-
           TreeDx.Store.get_repository_placement(repo_id),
         :ok <- ensure_placement_allows(mode, placement, local_node_id),
         {:ok, workspace} <-
           persist_workspace(repo, placement, principal, create_scope, %{
             mode: mode,
             base_ref: base_ref,
             base_commit_sha: base_resolved["target"],
             branch_name: branch_name,
             allowed_paths: allowed_paths,
             ttl: ttl
           }) do
      TreeDx.Audit.append("workspace.created", %{
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
    with {:ok, workspace} when is_map(workspace) <- TreeDx.Store.get_workspace(workspace_id),
         :ok <- workspace_actor_allowed(workspace, principal),
         {:ok, workspace, _scope} <- ensure_policy_current(workspace, principal, "files:read") do
      {:ok, public_workspace(workspace)}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      other -> other
    end
  end

  def close(workspace_id, principal) do
    with {:ok, workspace} when is_map(workspace) <- TreeDx.Store.get_workspace(workspace_id),
         :ok <- workspace_actor_allowed(workspace, principal),
         {:ok, _workspace, _scope} <- ensure_policy_current(workspace, principal, "files:read"),
         {:ok, closed} when is_map(closed) <- TreeDx.Store.close_workspace(workspace_id) do
      put_workspace_route(closed, principal, "closed")

      TreeDx.Audit.append("workspace.closed", %{
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
    TreeDx.Store.cleanup_expired_workspaces()
  end

  def quarantined(principal) do
    with {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "policy:read"),
         {:ok, workspaces} <- TreeDx.Store.list_quarantined_workspaces() do
      {:ok, %{workspaces: Enum.map(workspaces, &public_workspace/1)}}
    end
  end

  def ensure_policy_current(workspace, principal, capability) do
    cond do
      workspace["status"] in ["quarantined", "revoked"] ->
        revoked_error(workspace, workspace["policyVersion"])

      true ->
        with {:ok, current_scope} <-
               TreeDx.Capabilities.require_capability(
                 principal,
                 capability,
                 workspace["repositoryId"]
               ) do
          current_hash = current_scope["policyHash"]

          cond do
            is_nil(workspace["policyHash"]) or workspace["policyHash"] == current_hash ->
              maybe_update_policy(workspace, current_scope)

            scope_covers_workspace?(current_scope, workspace, capability) ->
              maybe_update_policy(workspace, current_scope)

            true ->
              quarantine(workspace, current_scope, "policy_scope_revoked")
          end
        else
          {:error, %{code: "permission_denied"}} ->
            quarantine(workspace, %{}, "policy_scope_revoked")

          {:error, %{"code" => "permission_denied"}} ->
            quarantine(workspace, %{}, "policy_scope_revoked")

          {:error, %{code: "not_found"}} ->
            quarantine(workspace, %{}, "policy_scope_revoked")

          {:error, %{"code" => "not_found"}} ->
            quarantine(workspace, %{}, "policy_scope_revoked")

          other ->
            other
        end
    end
  end

  defp maybe_update_policy(workspace, current_scope) do
    current_hash = current_scope["policyHash"]
    current_version = current_scope["policyVersion"]

    if is_binary(current_hash) and workspace["policyHash"] != current_hash do
      with {:ok, updated} <-
             TreeDx.Store.update_workspace_policy(%{
               workspaceId: workspace["id"],
               policyVersion: current_version,
               policyHash: current_hash
             }) do
        {:ok, updated, current_scope}
      end
    else
      {:ok, workspace, current_scope}
    end
  end

  defp quarantine(workspace, current_scope, reason) do
    {:ok, quarantined} =
      TreeDx.Store.quarantine_workspace(%{
        workspaceId: workspace["id"],
        policyVersion: current_scope["policyVersion"],
        policyHash: current_scope["policyHash"],
        reason: reason
      })

    TreeDx.Audit.append("workspace.quarantined", %{
      actor_id: workspace["actorId"],
      tenant_id: workspace["tenantId"],
      repo_id: workspace["repositoryId"],
      workspace_id: workspace["id"],
      status: "error",
      data: %{reason: reason}
    })

    revoked_error(quarantined, current_scope["policyVersion"])
  end

  defp revoked_error(workspace, current_policy_version) do
    {:error,
     %{
       code: "workspace_revoked",
       message: "Workspace policy has been revoked.",
       details: %{
         workspaceId: workspace["id"],
         policyVersion: workspace["policyVersion"],
         currentPolicyVersion: current_policy_version
       }
     }}
  end

  defp scope_covers_workspace?(scope, workspace, capability) do
    with true <- capability in (scope["capabilities"] || []),
         true <- TreeDx.Capabilities.allowed_repo?(scope, workspace["repositoryId"]),
         :ok <- TreeDx.Capabilities.require_ref(scope, workspace["baseRef"]),
         :ok <- require_branch_scope(scope, workspace["branchName"]),
         :ok <- TreeDx.Capabilities.require_paths(scope, workspace["allowedPaths"] || []) do
      true
    else
      _ -> false
    end
  end

  defp persist_workspace(repo, placement, principal, scope, opts) do
    workspace_id = TreeDx.Ids.workspace()
    materialized_path = Path.join([TreeDx.Store.data_dir(), "workspaces", "active", workspace_id])
    File.mkdir_p!(materialized_path)

    input = %{
      id: workspace_id,
      repositoryId: repo["id"],
      nodeId: placement["primaryNodeId"],
      actorId: actor_id(principal),
      tenantId: tenant_id(principal),
      baseRef: opts.base_ref,
      baseCommitSha: opts.base_commit_sha,
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
        paths: opts.allowed_paths,
        policyVersion: scope["policyVersion"],
        policyHash: scope["policyHash"]
      },
      policyVersion: scope["policyVersion"],
      policyHash: scope["policyHash"]
    }

    with {:ok, workspace} <- TreeDx.Store.put_workspace(input),
         :ok <- put_workspace_route(workspace, principal, "open") do
      {:ok, workspace}
    end
  end

  defp put_workspace_route(workspace, principal, status) do
    TreeDx.Store.put_workspace_route(%{
      workspaceId: workspace["id"],
      repositoryId: workspace["repositoryId"],
      nodeId: workspace["nodeId"],
      actorId: actor_id(principal),
      status: status,
      createdAt: workspace["createdAt"] || DateTime.utc_now() |> DateTime.to_iso8601(),
      updatedAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      expiresAt: workspace["expiresAt"]
    })

    :ok
  end

  defp normalize_mode("writable"), do: "writable"
  defp normalize_mode("read_only"), do: "read_only"
  defp normalize_mode("read-only"), do: "read_only"
  defp normalize_mode(_), do: "read_only"

  defp require_branch_scope(_scope, nil), do: :ok

  defp require_branch_scope(scope, branch_name),
    do: TreeDx.Capabilities.require_ref(scope, branch_name)

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
      "files:delete",
      "files:search",
      "workspace:exec:read_only",
      "workspace:exec:verification",
      "workspace:exec:write_limited",
      "git:diff",
      "git:commit"
    ]
  end

  defp workspace_capabilities(_),
    do: [
      "files:read",
      "files:search",
      "workspace:exec:read_only",
      "workspace:exec:verification",
      "git:diff"
    ]

  defp normalize_branch_name(nil), do: nil
  defp normalize_branch_name(""), do: ""
  defp normalize_branch_name("refs/" <> _ = branch_name), do: branch_name

  defp normalize_branch_name(branch_name) when is_binary(branch_name),
    do: "refs/heads/#{branch_name}"

  defp normalize_branch_name(branch_name), do: branch_name

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
      baseCommitSha: workspace["baseCommitSha"],
      branchName: workspace["branchName"],
      mode: workspace["mode"],
      status: workspace["status"],
      expiresAt: workspace["expiresAt"],
      commitSha: workspace["commitSha"],
      policyVersion: workspace["policyVersion"],
      policyHash: workspace["policyHash"],
      revokedAt: workspace["revokedAt"],
      revokedReason: workspace["revokedReason"],
      effectiveScope: workspace["effectiveScope"],
      capabilities: workspace["capabilities"]
    }
  end

  defp ensure_branch_start(_repo, nil, _base_sha), do: :ok

  defp ensure_branch_start(repo, branch_name, base_sha) do
    case TreeDx.Git.resolve_ref(TreeDx.RepositoryStorage.path!(repo), branch_name) do
      {:ok, %{"target" => ^base_sha}} ->
        :ok

      {:ok, _resolved} ->
        {:error,
         %{
           code: "conflict",
           message: "Workspace branch already exists at a different commit."
         }}

      {:error, %{"code" => "not_found"}} ->
        :ok

      {:error, %{code: "not_found"}} ->
        :ok

      other ->
        other
    end
  end
end
