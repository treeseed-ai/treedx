defmodule TreeDx.Pushes do
  @moduledoc false

  def push(repo_id, params, principal) do
    refspecs = params["refspecs"] || []

    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, "git:push", repo_id),
         :ok <- authorize_push_refspecs(scope, refspecs),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         {:ok, remote_url} <- remote_url(repo, params),
         :ok <- TreeDx.Git.RemoteUrl.reject_credential_url(remote_url),
         {:ok, credential} <- TreeDx.Git.Credentials.resolve(params["credentialId"]) do
      remote_name = params["remoteName"] || "origin"

      input = %{
        repoPath: TreeDx.RepositoryStorage.path!(repo),
        remoteUrl: remote_url,
        remoteName: remote_name,
        refspecs: refspecs,
        dryRun: truthy?(params["dryRun"]),
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
          dryRun: input.dryRun
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
              dryRun: result["status"] == "dry_run",
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
              dryRun: input.dryRun,
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

  def fetch(repo_id, params, principal) do
    with {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "git:fetch", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         :continue <- maybe_noop_fetch(repo, params, principal, repo_id),
         {:ok, remote_url} <- remote_url(repo, params),
         :ok <- TreeDx.Git.RemoteUrl.reject_credential_url(remote_url),
         {:ok, credential} <- TreeDx.Git.Credentials.resolve(params["credentialId"]) do
      remote_name = params["remoteName"] || "origin"

      input = %{
        repoPath: TreeDx.RepositoryStorage.path!(repo),
        remoteUrl: remote_url,
        remoteName: remote_name,
        refspecs: params["refspecs"] || ["+refs/heads/*:refs/remotes/#{remote_name}/*"],
        dryRun: truthy?(params["dryRun"]),
        credentialId: params["credentialId"]
      }

      case fetch_transport(input, credential) do
        {:ok, result} ->
          result = sanitize_result(result, repo_id)

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
              dryRun: result["status"] == "dry_run",
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
end
