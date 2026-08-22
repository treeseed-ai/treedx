defmodule TreeDx.Pushes do
  @moduledoc false

  def push(repo_id, params, principal) do
    refspecs = params["refspecs"] || []

    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, "git:push", repo_id),
         :ok <- authorize_push_refspecs(scope, refspecs),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         {:ok, remote_url} <- remote_url(repo, params),
         :ok <- TreeDx.Git.RemoteUrl.reject_credential_url(remote_url),
         {:ok, credential} <-
           TreeDx.Git.Credentials.resolve(
             params["credentialId"],
             credential_context("push", remote_url, refspecs)
           ) do
      remote_name = params["remoteName"] || "origin"

      input = %{
        repoPath: TreeDx.RepositoryStorage.path!(repo),
        remoteUrl: remote_url,
        remoteName: remote_name,
        refspecs: refspecs,
        plan: truthy?(params["planOnly"]),
        planOnly: truthy?(params["planOnly"]),
        expectedRemoteHead: params["expectedRemoteHead"],
        credentialId: params["credentialId"]
      }

      TreeDx.Audit.append("git.push.started", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "git.push",
        status: "started",
        data: %{
          remoteName: remote_name,
          remoteUrl: sanitize_remote_url(remote_url),
          refspecCount: length(refspecs),
          planOnly: input.planOnly
        }
      })

      case push_transport(input, credential) do
        {:ok, result} ->
          result = sanitize_result(result, repo_id)

          TreeDx.Audit.append("git.push.completed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "git.push",
            status: "ok",
            data: %{
              remoteName: result["remoteName"],
              remoteUrl: result["remoteUrl"],
              refspecCount: length(result["refspecs"] || []),
              planOnly: result["status"] == "plan",
              backend: result["backend"],
              updatedRefs: result["updatedRefs"] || []
            }
          })

          {:ok, %{push: result}}

        {:error, error} ->
          TreeDx.Audit.append("git.push.failed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "git.push",
            status: "error",
            data: %{
              remoteName: remote_name,
              remoteUrl: sanitize_remote_url(remote_url),
              refspecCount: length(refspecs),
              planOnly: input.planOnly,
              code: error["code"] || error[:code]
            }
          })

          {:error, error}
      end
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def promote(repo_id, params, principal) do
    source_ref = params["sourceRef"]
    destination_ref = params["destinationRef"]

    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, "git:push", repo_id),
         :ok <- require_promotable_ref(scope, source_ref),
         :ok <- require_promotable_ref(scope, destination_ref),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         true <- repo["remoteUrl"] in [nil, ""],
         {:ok, result} <-
           TreeDx.Git.promote_ref(
             TreeDx.RepositoryStorage.path!(repo),
             source_ref,
             destination_ref,
             params["expectedDestinationHead"]
           ),
         :ok <- TreeDx.RepositoryCache.invalidate_repository(repo_id) do
      TreeDx.Audit.append("git.ref_promoted", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "git.ref_promote",
        status: "ok",
        data: %{
          sourceRef: source_ref,
          destinationRef: destination_ref,
          beforeHead: result["beforeHead"],
          afterHead: result["afterHead"]
        }
      })

      {:ok, %{promotion: Map.put(result, "repoId", repo_id)}}
    else
      false ->
        {:error,
         %{
           code: "conflict",
           message:
             "Managed ref promotion is unavailable for repositories with an external remote."
         }}

      {:ok, nil} ->
        {:error, %{code: "not_found", message: "Repository not found."}}

      other ->
        other
    end
  end

  def retire(repo_id, params, principal) do
    ref_name = params["ref"]
    merged_into_ref = params["mergedIntoRef"]

    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, "git:push", repo_id),
         :ok <- require_promotable_ref(scope, ref_name),
         :ok <- require_promotable_ref(scope, merged_into_ref),
         true <- ref_name != merged_into_ref,
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         true <- ref_name != (repo["defaultRef"] || "refs/heads/main"),
         true <- repo["remoteUrl"] in [nil, ""],
         {:ok, result} <-
           TreeDx.Git.retire_ref(
             TreeDx.RepositoryStorage.path!(repo),
             ref_name,
             merged_into_ref,
             params["expectedHead"],
             params["expectedMergedIntoHead"]
           ),
         :ok <- TreeDx.RepositoryCache.invalidate_repository(repo_id) do
      TreeDx.Audit.append("git.ref_retired", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "git.ref_retire",
        status: "ok",
        data: %{
          ref: ref_name,
          mergedIntoRef: merged_into_ref,
          head: result["head"],
          mergedIntoHead: result["mergedIntoHead"],
          retirementStatus: result["status"]
        }
      })

      {:ok, %{retirement: Map.put(result, "repoId", repo_id)}}
    else
      false ->
        {:error,
         %{
           code: "validation_error",
           message:
             "The source ref cannot be protected, external, or identical to its merged destination."
         }}

      {:ok, nil} ->
        {:error, %{code: "not_found", message: "Repository not found."}}

      other ->
        other
    end
  end

  def discard_orphan(repo_id, params, principal) do
    ref_name = params["ref"]
    reason = String.trim(params["reason"] || "")

    with {:ok, push_scope} <-
           TreeDx.Capabilities.require_capability(principal, "git:push", repo_id),
         {:ok, policy_scope} <-
           TreeDx.Capabilities.require_capability(principal, "policy:write", repo_id),
         :ok <- require_promotable_ref(push_scope, ref_name),
         :ok <- require_promotable_ref(policy_scope, ref_name),
         true <- reason != "" and String.length(reason) <= 500,
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         true <- ref_name != (repo["defaultRef"] || "refs/heads/main"),
         true <- repo["remoteUrl"] in [nil, ""],
         {:ok, result} <-
           TreeDx.Git.discard_ref(
             TreeDx.RepositoryStorage.path!(repo),
             ref_name,
             params["expectedHead"]
           ),
         :ok <- TreeDx.RepositoryCache.invalidate_repository(repo_id) do
      TreeDx.Audit.append("git.orphan_ref_discarded", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "git.orphan_ref_discard",
        status: "ok",
        data: %{
          ref: ref_name,
          head: result["head"],
          discardStatus: result["status"],
          reason: reason
        }
      })

      {:ok, %{discard: Map.put(result, "repoId", repo_id)}}
    else
      false ->
        {:error,
         %{
           code: "validation_error",
           message:
             "Orphan ref discard requires a reason and a managed, non-default, locally held ref."
         }}

      {:ok, nil} ->
        {:error, %{code: "not_found", message: "Repository not found."}}

      other ->
        other
    end
  end

  def fetch(repo_id, params, principal) do
    with {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "git:fetch", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         :continue <- maybe_noop_fetch(repo, params, principal, repo_id),
         {:ok, remote_url} <- remote_url(repo, params),
         :ok <- TreeDx.Git.RemoteUrl.reject_credential_url(remote_url),
         {:ok, credential} <-
           TreeDx.Git.Credentials.resolve(
             params["credentialId"],
             credential_context(
               "fetch",
               remote_url,
               params["refspecs"] ||
                 ["+refs/heads/*:refs/remotes/#{params["remoteName"] || "origin"}/*"]
             )
           ) do
      remote_name = params["remoteName"] || "origin"

      input = %{
        repoPath: TreeDx.RepositoryStorage.path!(repo),
        remoteUrl: remote_url,
        remoteName: remote_name,
        refspecs: params["refspecs"] || ["+refs/heads/*:refs/remotes/#{remote_name}/*"],
        plan: truthy?(params["planOnly"]),
        planOnly: truthy?(params["planOnly"]),
        credentialId: params["credentialId"]
      }

      case fetch_transport(input, credential) do
        {:ok, result} ->
          result = sanitize_result(result, repo_id)

          if result["status"] != "plan" do
            TreeDx.RepositoryCache.invalidate_repository(repo_id)
          end

          TreeDx.Audit.append("git.fetch.completed", %{
            actor_id: principal["actorId"],
            tenant_id: principal["tenantId"],
            repo_id: repo_id,
            operation: "git.fetch",
            status: "ok",
            data: %{
              remoteName: result["remoteName"],
              remoteUrl: result["remoteUrl"],
              refspecCount: length(result["refspecs"] || []),
              planOnly: result["status"] == "plan",
              updatedRefs: result["updatedRefs"] || []
            }
          })

          {:ok, %{fetch: result}}

        other ->
          other
      end
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      {:ok, result} -> {:ok, result}
      other -> other
    end
  end

  def sanitize_remote_url(nil), do: nil
  def sanitize_remote_url(url), do: TreeDx.Git.RemoteUrl.sanitize(url)

  defp remote_url(repo, params) do
    url = params["remoteUrl"] || repo["remoteUrl"]

    if is_binary(url) and String.trim(url) != "" do
      {:ok, url}
    else
      {:error, %{code: "validation_error", message: "remoteUrl is required."}}
    end
  end

  defp maybe_noop_fetch(repo, params, principal, repo_id) do
    if is_nil(params["remoteUrl"]) and is_nil(repo["remoteUrl"]) do
      with {:ok, git} <- TreeDx.Git.inspect_repository(TreeDx.RepositoryStorage.path!(repo)) do
        TreeDx.Audit.append("git.fetch.completed", %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          repo_id: repo_id,
          operation: "git.fetch",
          status: "noop",
          data: %{refreshed: false}
        })

        {:ok,
         %{
           repo: public_repo(repo),
           refreshed: false,
           git: Map.drop(git, ["path", "repoPath", "gitDir", "worktreePath"])
         }}
      end
    else
      :continue
    end
  end

  defp public_repo(repo) do
    %{
      repoId: repo["id"],
      name: repo["name"],
      defaultRef: repo["defaultRef"],
      status: repo["status"],
      remoteUrl: repo["remoteUrl"]
    }
  end

  defp authorize_push_refspecs(scope, refspecs) when is_list(refspecs) and refspecs != [] do
    refspecs
    |> Enum.map(&push_ref_pair/1)
    |> Enum.reduce_while(:ok, fn
      {:ok, {source, destination}}, :ok ->
        with :ok <- TreeDx.Capabilities.require_ref(scope, source),
             :ok <- TreeDx.Capabilities.require_ref(scope, destination) do
          {:cont, :ok}
        else
          error -> {:halt, error}
        end

      {:error, error}, :ok ->
        {:halt, {:error, error}}
    end)
  end

  defp authorize_push_refspecs(_scope, _refspecs),
    do: {:error, %{code: "validation_error", message: "refspecs are required."}}

  defp require_promotable_ref(scope, ref) when is_binary(ref) and ref != "" do
    if String.starts_with?(ref, "refs/heads/"),
      do: TreeDx.Capabilities.require_ref(scope, ref),
      else:
        {:error, %{code: "validation_error", message: "Promotion refs must be full branch refs."}}
  end

  defp require_promotable_ref(_scope, _ref),
    do:
      {:error, %{code: "validation_error", message: "sourceRef and destinationRef are required."}}

  defp push_ref_pair(refspec) when is_binary(refspec) do
    stripped = String.trim_leading(refspec, "+")

    cond do
      String.contains?(stripped, "*") ->
        {:error,
         %{code: "validation_error", message: "wildcard push refspecs are not supported."}}

      true ->
        case String.split(stripped, ":", parts: 2) do
          [source, destination] when source != "" and destination != "" ->
            {:ok, {source, destination}}

          _ ->
            {:error, %{code: "validation_error", message: "invalid push refspec."}}
        end
    end
  end

  defp push_ref_pair(_),
    do: {:error, %{code: "validation_error", message: "invalid push refspec."}}

  defp push_transport(input, credential) do
    if TreeDx.Git.ExternalTransport.required?(input.remoteUrl, input.credentialId) do
      TreeDx.Git.ExternalTransport.push(input, credential)
    else
      TreeDx.Git.push_remote(input)
    end
  end

  defp fetch_transport(input, credential) do
    if TreeDx.Git.ExternalTransport.required?(input.remoteUrl, input.credentialId) do
      TreeDx.Git.ExternalTransport.fetch(input, credential)
    else
      TreeDx.Git.fetch_remote(input)
    end
  end

  defp sanitize_result(result, repo_id) do
    result
    |> Map.put("repoId", repo_id)
    |> Map.update("remoteUrl", nil, &sanitize_remote_url/1)
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp credential_context(operation, remote_url, refspecs) do
    %{
      operation: operation,
      allowedHost: URI.parse(remote_url).host,
      refspecDigest:
        :crypto.hash(:sha256, Enum.join(refspecs, "\n")) |> Base.encode16(case: :lower)
    }
  end
end
