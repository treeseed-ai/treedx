defmodule TreeDb.Snapshots do
  @moduledoc false

  alias TreeDb.Files.PathPolicy
  alias TreeDb.RepositoryQuery.PathMatch

  @default_kind "repository_snapshot"
  @default_max_file_bytes 10_485_760
  @default_max_total_bytes 104_857_600

  def build(repo_id, params, principal) do
    with {:ok, ctx} <- build_context(repo_id, params, principal),
         :ok <- audit_started(ctx, params),
         {:ok, files} <- collect_files(ctx),
         {:ok, manifest} <- persist_snapshot(ctx, files) do
      TreeDb.Audit.append(
        "snapshot.built",
        audit_attrs(ctx, %{snapshotId: manifest["snapshotId"]})
      )

      {:ok, %{snapshot: public_snapshot(manifest)}}
    else
      {:error, error} = failure ->
        TreeDb.Audit.append("snapshot.build.failed", %{
          actor_id: principal && principal["actorId"],
          tenant_id: principal && principal["tenantId"],
          repo_id: repo_id,
          operation: "snapshot.build",
          status: "error",
          data: %{code: error["code"] || error[:code]}
        })

        failure
    end
  end

  def get(repo_id, snapshot_id, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_any(
             principal,
             ["snapshot:build", "artifact:export"],
             repo_id
           ),
         {:ok, manifest} when is_map(manifest) <- TreeDb.Store.get_snapshot_manifest(snapshot_id),
         :ok <- ensure_repo(manifest, repo_id) do
      {:ok, %{snapshot: public_snapshot(manifest)}}
    else
      {:ok, nil} -> {:error, %{code: "snapshot_not_found", message: "Snapshot not found."}}
      other -> other
    end
  end

  def export(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(principal, "artifact:export", repo_id),
         {:ok, manifest} <- manifest_for_export(repo_id, params, principal),
         artifact when is_map(artifact) <- manifest["artifact"] || manifest[:artifact] do
      TreeDb.Audit.append("artifact.exported", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "artifact.export",
        status: "ok",
        data: %{
          snapshotId: manifest["snapshotId"],
          artifactId: artifact["artifactId"]
        }
      })

      {:ok, %{artifact: public_artifact(artifact, repo_id)}}
    else
      nil -> {:error, %{code: "artifact_not_found", message: "Artifact not found."}}
      other -> other
    end
  end

  def download(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(principal, "artifact:export", repo_id),
         {:ok, manifest} <- manifest_for_export(repo_id, params, principal),
         artifact when is_map(artifact) <- manifest["artifact"] || manifest[:artifact],
         {:ok, %{"contentBase64" => content}} <-
           TreeDb.Store.read_artifact_bytes(manifest["snapshotId"]),
         {:ok, bytes} <- Base.decode64(content || "") do
      TreeDb.Audit.append("artifact.downloaded", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "artifact.download",
        status: "ok",
        data: %{
          snapshotId: manifest["snapshotId"],
          artifactId: artifact["artifactId"]
        }
      })

      {:ok,
       %{
         snapshot: public_snapshot(manifest),
         artifact: public_artifact(artifact, repo_id),
         bytes: bytes
       }}
    else
      nil -> {:error, %{code: "artifact_not_found", message: "Artifact not found."}}
      :error -> {:error, %{code: "artifact_not_found", message: "Artifact not found."}}
      other -> other
    end
  end

  defp build_context(repo_id, params, principal) do
    with {:ok, scope} <-
           TreeDb.Capabilities.require_all(
             principal,
             ["snapshot:build", "files:read", "git:read"],
             repo_id
           ),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         :ok <- TreeDb.Capabilities.require_ref(scope, ref),
         {:ok, resolved_ref} <- TreeDb.Git.resolve_ref(repo["localPath"], ref),
         {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"] || ["**"]),
         :ok <- TreeDb.Capabilities.require_paths(scope, patterns) do
      {:ok,
       %{
         repo_id: repo_id,
         repo: repo,
         principal: principal,
         scope: scope,
         ref: ref,
         commit_sha: resolved_ref["target"],
         patterns: patterns,
         kind: params["kind"] || @default_kind,
         allow_protected: params["allowProtected"] == true,
         include_graph: params["includeGraph"] != false,
         max_file_bytes: env_int("TREEDB_SNAPSHOT_MAX_FILE_BYTES", @default_max_file_bytes),
         max_total_bytes: env_int("TREEDB_SNAPSHOT_MAX_TOTAL_BYTES", @default_max_total_bytes)
       }}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  defp collect_files(ctx) do
    with {:ok, entries} <-
           TreeDb.Git.list_tree_recursive(ctx.repo["localPath"], ctx.commit_sha, nil) do
      entries
      |> Enum.filter(&(&1["kind"] == "blob"))
      |> Enum.filter(&PathMatch.match_any?(ctx.patterns, &1["path"]))
      |> Enum.filter(&TreeDb.Capabilities.allowed_path?(ctx.scope, &1["path"]))
      |> Enum.reject(&(PathPolicy.protected?(&1["path"]) and !ctx.allow_protected))
      |> Enum.reduce_while({:ok, [], 0}, fn entry, {:ok, acc, total} ->
        with {:ok, blob} <-
               TreeDb.Git.read_blob(ctx.repo["localPath"], ctx.commit_sha, entry["path"]),
             {:ok, bytes} <- Base.decode64(blob["contentBase64"]) do
          size = byte_size(bytes)
          total = total + size

          cond do
            size > ctx.max_file_bytes ->
              {:halt,
               {:error, %{code: "payload_too_large", message: "Snapshot file is too large."}}}

            total > ctx.max_total_bytes ->
              {:halt, {:error, %{code: "payload_too_large", message: "Snapshot is too large."}}}

            true ->
              file = %{
                path: entry["path"],
                objectId: entry["objectId"],
                contentBase64: blob["contentBase64"]
              }

              {:cont, {:ok, [file | acc], total}}
          end
        else
          other -> {:halt, other}
        end
      end)
      |> case do
        {:ok, files, _total} -> {:ok, Enum.reverse(files)}
        error -> error
      end
    end
  end

  defp persist_snapshot(ctx, files) do
    graph_version =
      if ctx.include_graph do
        case TreeDb.Graph.Native.read_latest_graph_manifest(ctx.repo_id, ctx.ref) do
          {:ok, manifest} when is_map(manifest) -> manifest["graphVersion"]
          _ -> nil
        end
      end

    TreeDb.Store.build_snapshot_artifact(%{
      repoId: ctx.repo_id,
      refName: ctx.ref,
      commitSha: ctx.commit_sha,
      kind: ctx.kind,
      includedPaths: ctx.patterns,
      graphVersion: graph_version,
      files: files,
      createdByActorId: ctx.principal["actorId"]
    })
  end

  defp manifest_for_export(repo_id, %{"snapshotId" => snapshot_id}, _principal)
       when is_binary(snapshot_id) do
    with {:ok, manifest} when is_map(manifest) <- TreeDb.Store.get_snapshot_manifest(snapshot_id),
         :ok <- ensure_repo(manifest, repo_id) do
      {:ok, manifest}
    else
      {:ok, nil} -> {:error, %{code: "snapshot_not_found", message: "Snapshot not found."}}
      other -> other
    end
  end

  defp manifest_for_export(repo_id, params, principal) do
    with {:ok, %{snapshot: snapshot}} <- build(repo_id, params, principal),
         {:ok, manifest} when is_map(manifest) <-
           TreeDb.Store.get_snapshot_manifest(snapshot["snapshotId"]) do
      {:ok, manifest}
    end
  end

  defp ensure_repo(manifest, repo_id) do
    if manifest["repoId"] == repo_id do
      :ok
    else
      {:error, %{code: "not_found", message: "Snapshot not found."}}
    end
  end

  defp public_snapshot(manifest) do
    manifest
    |> Map.put("ref", manifest["refName"])
    |> Map.delete("refName")
    |> Map.update("artifact", nil, fn
      nil -> nil
      artifact -> public_artifact(artifact, manifest["repoId"])
    end)
  end

  defp public_artifact(artifact, repo_id) do
    snapshot_id = artifact["snapshotId"]

    artifact
    |> Map.put(
      "downloadUrl",
      "/api/v1/repos/#{repo_id}/artifacts/export?snapshotId=#{snapshot_id}&download=true"
    )
  end

  defp audit_started(ctx, _params) do
    TreeDb.Audit.append("snapshot.build.started", audit_attrs(ctx, %{}))
    :ok
  end

  defp audit_attrs(ctx, data) do
    %{
      actor_id: ctx.principal["actorId"],
      tenant_id: ctx.principal["tenantId"],
      repo_id: ctx.repo_id,
      operation: "snapshot.build",
      status: "ok",
      data: Map.merge(%{ref: ctx.ref, commitSha: ctx.commit_sha, paths: ctx.patterns}, data)
    }
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {int, _} when int > 0 -> int
          _ -> default
        end
    end
  end
end
