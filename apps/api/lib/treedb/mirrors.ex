defmodule TreeDb.Mirrors do
  @moduledoc false

  def list(repo_id, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_all(principal, ["registry:read", "mirror:read"], repo_id),
         {:ok, mirrors} <- TreeDb.Store.list_mirrors(repo_id) do
      {:ok, %{mirrors: mirrors}}
    end
  end

  def create(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_all(principal, ["mirror:write", "registry:write"], repo_id) do
      input = %{
        id: params["id"] || "",
        repositoryId: repo_id,
        sourceNodeId: params["sourceNodeId"] || "node_local",
        targetNodeId: params["targetNodeId"] || "node_mirror",
        mode: params["mode"] || "read_replica",
        lastSeenCommit: params["lastSeenCommit"],
        behindBy: params["behindBy"],
        status: params["status"] || "planned"
      }

      TreeDb.Store.put_mirror(input)
      |> case do
        {:ok, mirror} ->
          TreeDb.Audit.append("mirror.created", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "mirror.create",
            status: "ok"
          })

          {:ok, %{mirror: mirror}}

        other ->
          other
      end
    end
  end

  def sync(repo_id, mirror_id, params, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_all(
             principal,
             ["mirror:write", "git:fetch", "registry:write"],
             repo_id
           ),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         {:ok, mirror} <- get_mirror(repo_id, mirror_id) do
      remote_name = params["remoteName"] || "origin"
      refspecs = params["refspecs"] || ["+refs/heads/*:refs/remotes/#{remote_name}/*"]
      started_at = DateTime.utc_now() |> DateTime.to_iso8601()

      TreeDb.Audit.append("mirror.sync.started", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "mirror.sync",
        status: "started",
        data: %{mirrorId: mirror_id, remoteName: remote_name}
      })

      input = %{
        repoPath: repo["localPath"],
        remoteUrl: params["remoteUrl"] || repo["remoteUrl"],
        remoteName: remote_name,
        refspecs: refspecs,
        dryRun: params["dryRun"] == true
      }

      case TreeDb.Git.fetch_remote(input) do
        {:ok, result} ->
          sync_record =
            put_sync_record(
              mirror,
              repo_id,
              result,
              started_at,
              "synced",
              nil,
              params["remoteUrl"]
            )

          updated_mirror =
            mirror
            |> Map.put("lastSeenCommit", result["afterHead"])
            |> Map.put("behindBy", if(result["afterHead"], do: 0, else: nil))
            |> Map.put("status", "synced")

          with {:ok, mirror} <- TreeDb.Store.put_mirror(updated_mirror),
               {:ok, sync} <- sync_record do
            TreeDb.Audit.append("mirror.sync.completed", %{
              actor_id: principal["actorId"],
              tenant_id: principal["tenantId"],
              repo_id: repo_id,
              operation: "mirror.sync",
              status: "ok",
              data: %{mirrorId: mirror_id, updatedRefs: result["updatedRefs"] || []}
            })

            {:ok, %{mirror: mirror, sync: sync}}
          end

        {:error, error} ->
          _ =
            put_sync_record(
              mirror,
              repo_id,
              %{"remoteName" => remote_name, "refspecs" => refspecs},
              started_at,
              "failed",
              error["message"] || error[:message],
              params["remoteUrl"]
            )

          failed_mirror = mirror |> Map.put("status", "failed")
          _ = TreeDb.Store.put_mirror(failed_mirror)

          TreeDb.Audit.append("mirror.sync.failed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "mirror.sync",
            status: "error",
            data: %{mirrorId: mirror_id, code: error["code"] || error[:code]}
          })

          {:error, error}
      end
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def health(repo_id, mirror_id, _params, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_all(principal, ["mirror:read", "registry:read"], repo_id),
         {:ok, mirror} <- get_mirror(repo_id, mirror_id) do
      status =
        cond do
          mirror["status"] == "synced" and mirror["behindBy"] in [nil, 0] -> "healthy"
          mirror["status"] == "failed" -> "unhealthy"
          true -> "degraded"
        end

      result = %{
        mirrorId: mirror_id,
        repoId: repo_id,
        status: status,
        mirrorStatus: mirror["status"],
        behindBy: mirror["behindBy"],
        lastSeenCommit: mirror["lastSeenCommit"]
      }

      TreeDb.Audit.append("mirror.health_checked", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "mirror.health",
        status: status,
        data: %{mirrorId: mirror_id, behindBy: mirror["behindBy"]}
      })

      {:ok, %{health: result}}
    end
  end

  def promote(repo_id, mirror_id, params, principal) do
    dry_run = params["dryRun"] != false
    capability = if dry_run, do: "migration:read", else: "migration:write"

    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, capability, repo_id),
         {:ok, mirror} <- get_mirror(repo_id, mirror_id),
         :ok <- require_synced(mirror, params),
         {:ok, placement} <- TreeDb.Store.get_repository_placement(repo_id) do
      resulting =
        (placement ||
           %{
             "repositoryId" => repo_id,
             "primaryNodeId" => mirror["sourceNodeId"],
             "mirrorNodeIds" => [],
             "readPolicy" => "primary_or_mirror",
             "writePolicy" => "primary_only",
             "migrationState" => "stable"
           })
        |> Map.put("primaryNodeId", mirror["targetNodeId"])
        |> Map.put("migrationState", if(dry_run, do: "planned", else: "stable"))

      event = if(dry_run, do: "mirror.promotion_planned", else: "mirror.promoted")

      result = %{
        mirrorId: mirror_id,
        repoId: repo_id,
        dryRun: dry_run,
        status: if(dry_run, do: "planned", else: "promoted"),
        previousPlacement: placement,
        resultingPlacement: resulting
      }

      result =
        if dry_run do
          result
        else
          {:ok, stored} = TreeDb.Store.put_repository_placement(resulting)
          Map.put(result, :resultingPlacement, stored)
        end

      TreeDb.Audit.append(event, %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "mirror.promote",
        status: "ok",
        data: %{mirrorId: mirror_id, dryRun: dry_run}
      })

      {:ok, %{promotion: result}}
    end
  end

  defp get_mirror(repo_id, mirror_id) do
    with {:ok, mirrors} <- TreeDb.Store.list_mirrors(repo_id) do
      case Enum.find(mirrors, &(&1["id"] == mirror_id)) do
        nil -> {:error, %{code: "not_found", message: "Mirror not found."}}
        mirror -> {:ok, mirror}
      end
    end
  end

  defp put_sync_record(mirror, repo_id, result, started_at, status, error, remote_url) do
    TreeDb.Store.put_mirror_sync(%{
      id: "",
      mirrorId: mirror["id"],
      repositoryId: repo_id,
      sourceNodeId: mirror["sourceNodeId"],
      targetNodeId: mirror["targetNodeId"],
      remoteUrl: sanitize_remote_input(remote_url),
      remoteName: result["remoteName"] || "origin",
      refspecs: result["refspecs"] || [],
      beforeCommit: result["beforeHead"],
      afterCommit: result["afterHead"],
      updatedRefs: result["updatedRefs"] || [],
      receivedPack: result["receivedPack"] == true,
      behindBy: if(status == "synced", do: 0, else: nil),
      status: status,
      error: error,
      startedAt: started_at,
      completedAt: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp sanitize_remote_input(nil), do: nil

  defp sanitize_remote_input(url) when is_binary(url) do
    TreeDb.Pushes.sanitize_remote_url(url)
  end

  defp require_synced(mirror, params) do
    if params["requireSynced"] == true and
         not (mirror["status"] == "synced" and mirror["behindBy"] in [nil, 0]) do
      {:error, %{code: "conflict", message: "Mirror is not synced."}}
    else
      :ok
    end
  end
end
