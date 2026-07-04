defmodule TreeDx.Mirrors do
  @moduledoc false

  def list(repo_id, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_all(principal, ["registry:read", "mirror:read"], repo_id),
         {:ok, mirrors} <- TreeDx.Store.list_mirrors(repo_id) do
      {:ok, %{mirrors: mirrors}}
    end
  end

  def create(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_all(principal, ["mirror:write", "registry:write"], repo_id) do
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

      TreeDx.Store.put_mirror(input)
      |> case do
        {:ok, mirror} ->
          TreeDx.Audit.append("mirror.created", %{
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
           TreeDx.Capabilities.require_all(
             principal,
             ["mirror:write", "git:fetch", "registry:write"],
             repo_id
           ),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         {:ok, mirror} <- get_mirror(repo_id, mirror_id) do
      if federation_peer?(mirror["targetNodeId"]) and params["remoteUrl"] in [nil, ""] do
        sync_federation_mirror(repo_id, mirror, principal)
      else
        sync_git_remote(
          repo_id,
          repo,
          mirror,
          mirror_id,
          params,
          principal,
          conn_request_id(params)
        )
      end
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  defp sync_git_remote(repo_id, repo, mirror, mirror_id, params, principal, _request_id) do
    remote_name = params["remoteName"] || "origin"
    refspecs = params["refspecs"] || ["+refs/heads/*:refs/remotes/#{remote_name}/*"]
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    TreeDx.Audit.append("mirror.sync.started", %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      repo_id: repo_id,
      operation: "mirror.sync",
      status: "started",
      data: %{mirrorId: mirror_id, remoteName: remote_name}
    })

    input = %{
      repoPath: TreeDx.RepositoryStorage.path!(repo),
      remoteUrl: params["remoteUrl"] || repo["remoteUrl"],
      remoteName: remote_name,
      refspecs: refspecs,
      plan: params["planOnly"] == true,
      planOnly: params["planOnly"] == true
    }

    case fetch_or_plan(repo, input) do
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

        with {:ok, mirror} <- TreeDx.Store.put_mirror(updated_mirror),
             {:ok, sync} <- sync_record do
          TreeDx.Audit.append("mirror.sync.completed", %{
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
        _ = TreeDx.Store.put_mirror(failed_mirror)

        TreeDx.Audit.append("mirror.sync.failed", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          repo_id: repo_id,
          operation: "mirror.sync",
          status: "error",
          data: %{mirrorId: mirror_id, code: error["code"] || error[:code]}
        })

        {:error, error}
    end
  end

  defp sync_federation_mirror(repo_id, mirror, principal) do
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    TreeDx.Audit.append("mirror.sync.started", %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      repo_id: repo_id,
      operation: "mirror.sync",
      status: "started",
      data: %{mirrorId: mirror["id"], targetNodeId: mirror["targetNodeId"]}
    })

    case TreeDx.Federation.MirrorTransfer.sync_remote(repo_id, mirror["targetNodeId"]) do
      {:ok, result} ->
        updated_mirror =
          mirror
          |> Map.put("lastSeenCommit", result["lastSyncedCommit"] || mirror["lastSeenCommit"])
          |> Map.put("behindBy", 0)
          |> Map.put("status", "synced")

        with {:ok, stored_mirror} <- TreeDx.Store.put_mirror(updated_mirror),
             {:ok, sync} <-
               put_sync_record(
                 mirror,
                 repo_id,
                 %{
                   "remoteName" => "federation:#{mirror["targetNodeId"]}",
                   "refspecs" => ["+refs/*:refs/*"],
                   "beforeHead" => mirror["lastSeenCommit"],
                   "afterHead" => updated_mirror["lastSeenCommit"],
                   "updatedRefs" => []
                 },
                 started_at,
                 "synced",
                 nil,
                 nil
               ) do
          TreeDx.Audit.append("mirror.sync.completed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "mirror.sync",
            status: "ok",
            data: %{mirrorId: mirror["id"], targetNodeId: mirror["targetNodeId"]}
          })

          {:ok, %{mirror: stored_mirror, sync: sync, transfer: result}}
        end

      {:error, error} ->
        _ =
          put_sync_record(
            mirror,
            repo_id,
            %{"remoteName" => "federation:#{mirror["targetNodeId"]}", "refspecs" => []},
            started_at,
            "failed",
            error["message"] || error[:message],
            nil
          )

        _ = TreeDx.Store.put_mirror(Map.put(mirror, "status", "failed"))
        {:error, error}
    end
  end

  def health(repo_id, mirror_id, _params, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_all(principal, ["mirror:read", "registry:read"], repo_id),
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

      TreeDx.Audit.append("mirror.health_checked", %{
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
    plan = params["planOnly"] != false
    capability = if plan, do: "migration:read", else: "migration:write"

    with {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, capability, repo_id),
         {:ok, mirror} <- get_mirror(repo_id, mirror_id),
         :ok <- require_synced(mirror, params),
         {:ok, placement} <- TreeDx.Store.get_repository_placement(repo_id) do
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
        |> Map.put("migrationState", if(plan, do: "planned", else: "stable"))

      event = if(plan, do: "mirror.promotion_planned", else: "mirror.promoted")

      result = %{
        mirrorId: mirror_id,
        repoId: repo_id,
        planOnly: plan,
        status: if(plan, do: "planned", else: "promoted"),
        previousPlacement: placement,
        resultingPlacement: resulting
      }

      result =
        if plan do
          result
        else
          {:ok, stored} = TreeDx.Store.put_repository_placement(resulting)
          Map.put(result, :resultingPlacement, stored)
        end

      TreeDx.Audit.append(event, %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "mirror.promote",
        status: "ok",
        data: %{mirrorId: mirror_id, planOnly: plan}
      })

      {:ok, %{promotion: result}}
    end
  end

  defp get_mirror(repo_id, mirror_id) do
    with {:ok, mirrors} <- TreeDx.Store.list_mirrors(repo_id) do
      case Enum.find(mirrors, &(&1["id"] == mirror_id)) do
        nil -> {:error, %{code: "not_found", message: "Mirror not found."}}
        mirror -> {:ok, mirror}
      end
    end
  end

  defp fetch_or_plan(repo, %{planOnly: true} = input) do
    with {:ok, git} <- TreeDx.Git.inspect_repository(TreeDx.RepositoryStorage.path!(repo)) do
      {:ok,
       %{
         "remoteName" => input.remoteName,
         "remoteUrl" => input.remoteUrl,
         "refspecs" => input.refspecs,
         "updatedRefs" => [],
         "receivedPack" => false,
         "beforeHead" => git["head"],
         "afterHead" => git["head"],
         "status" => "plan"
       }}
    end
  end

  defp fetch_or_plan(_repo, input), do: TreeDx.Git.fetch_remote(input)

  defp put_sync_record(mirror, repo_id, result, started_at, status, error, remote_url) do
    TreeDx.Store.put_mirror_sync(%{
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
    TreeDx.Pushes.sanitize_remote_url(url)
  end

  defp require_synced(mirror, params) do
    if params["requireSynced"] == true and
         not (mirror["status"] == "synced" and mirror["behindBy"] in [nil, 0]) do
      {:error, %{code: "conflict", message: "Mirror is not synced."}}
    else
      :ok
    end
  end

  defp federation_peer?(node_id) do
    with {:ok, peer} when is_map(peer) <- TreeDx.Store.get_federation_peer(node_id) do
      is_binary(peer["baseUrl"]) and peer["baseUrl"] != ""
    else
      _ -> false
    end
  end

  defp conn_request_id(_params), do: nil
end
