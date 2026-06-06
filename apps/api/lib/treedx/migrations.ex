defmodule TreeDx.Migrations do
  @moduledoc false

  def create(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_all(
             principal,
             ["migration:write", "registry:write", "repos:write"],
             repo_id
           ),
         {:ok, placement} when is_map(placement) <-
           TreeDx.Store.get_repository_placement(repo_id),
         {:ok, _target_node} <- target_node(params["targetNodeId"]),
         :ok <- validate_synced_mirror(repo_id, params, placement) do
      dry_run = params["dryRun"] == true
      now = DateTime.utc_now() |> DateTime.to_iso8601()
      source_node_id = params["sourceNodeId"] || placement["primaryNodeId"]
      target_node_id = params["targetNodeId"]
      resulting_placement = resulting_placement(placement, target_node_id)

      record = %{
        id: "",
        repositoryId: repo_id,
        sourceNodeId: source_node_id,
        targetNodeId: target_node_id,
        mode: params["mode"] || "primary_transfer",
        status: if(dry_run, do: "planned", else: "completed"),
        dryRun: dry_run,
        requireMirrorSynced: params["requireMirrorSynced"] != false,
        previousPlacement: placement,
        resultingPlacement: if(dry_run, do: nil, else: resulting_placement),
        validation: %{mirrorSynced: true},
        createdByActorId: principal["actorId"],
        createdAt: now,
        completedAt: if(dry_run, do: nil, else: now)
      }

      with {:ok, migration} <- TreeDx.Store.put_migration(record),
           {:ok, placement} <- maybe_update_placement(dry_run, resulting_placement) do
        TreeDx.Audit.append("migration.created", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          repo_id: repo_id,
          operation: "migration.create",
          status: if(dry_run, do: "planned", else: "ok"),
          data: %{migrationId: migration["id"], targetNodeId: target_node_id}
        })

        if !dry_run do
          TreeDx.Audit.append("migration.completed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "migration.complete",
            status: "ok",
            data: %{migrationId: migration["id"], targetNodeId: target_node_id}
          })
        end

        {:ok, %{migration: migration, placement: placement}}
      end
    else
      {:ok, nil} ->
        {:error, %{code: "not_found", message: "Placement not found."}}

      {:error, error} = failure ->
        TreeDx.Audit.append("migration.failed", %{
          actor_id: principal && principal["actorId"],
          tenant_id: principal && principal["tenantId"],
          repo_id: repo_id,
          operation: "migration.create",
          status: "error",
          data: %{code: error["code"] || error[:code]}
        })

        failure
    end
  end

  def get(repo_id, migration_id, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_all(
             principal,
             ["migration:read", "registry:read"],
             repo_id
           ),
         {:ok, migration} when is_map(migration) <-
           TreeDx.Store.get_migration(repo_id, migration_id) do
      {:ok, %{migration: migration}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Migration not found."}}
      other -> other
    end
  end

  defp target_node(nil),
    do: {:error, %{code: "validation_error", message: "targetNodeId is required."}}

  defp target_node(node_id) do
    case TreeDx.Store.get_node(node_id) do
      {:ok, nil} -> federation_target_node(node_id)
      {:ok, node} -> {:ok, node}
      other -> other
    end
  end

  defp federation_target_node(node_id) do
    case TreeDx.Federation.Trust.get(node_id) do
      {:ok, peer} when is_map(peer) ->
        states =
          peer["trustStates"] || peer[:trustStates] || peer["trust_states"] || peer[:trust_states] ||
            []

        can_mirror? =
          truthy?(
            peer["canMirrorRepos"] || peer[:canMirrorRepos] || peer["can_mirror_repos"] ||
              peer[:can_mirror_repos]
          )

        if "trusted_for_mirror" in states or can_mirror? do
          {:ok, %{"id" => node_id, "kind" => "federation_peer"}}
        else
          {:error, %{code: "not_found", message: "Target node not found."}}
        end

      _ ->
        {:error, %{code: "not_found", message: "Target node not found."}}
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp validate_synced_mirror(_repo_id, %{"requireMirrorSynced" => false}, _placement), do: :ok

  defp validate_synced_mirror(repo_id, params, _placement) do
    target_node_id = params["targetNodeId"]

    with {:ok, mirrors} <- TreeDx.Store.list_mirrors(repo_id) do
      if Enum.any?(mirrors, &(&1["targetNodeId"] == target_node_id and &1["status"] == "synced")) do
        :ok
      else
        {:error,
         %{code: "migration_conflict", message: "Target mirror must be synced before migration."}}
      end
    end
  end

  defp resulting_placement(placement, target_node_id) do
    previous_primary = placement["primaryNodeId"]

    mirror_node_ids =
      placement
      |> Map.get("mirrorNodeIds", [])
      |> Enum.reject(&(&1 == target_node_id))
      |> then(fn mirrors -> Enum.uniq([previous_primary | mirrors]) end)

    placement
    |> Map.put("primaryNodeId", target_node_id)
    |> Map.put("mirrorNodeIds", mirror_node_ids)
    |> Map.put("migrationState", "stable")
  end

  defp maybe_update_placement(true, placement), do: {:ok, placement}

  defp maybe_update_placement(false, placement),
    do: TreeDx.Store.put_repository_placement(placement)
end
