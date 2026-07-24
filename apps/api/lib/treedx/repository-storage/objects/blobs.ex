defmodule TreeDx.Blobs do
  @moduledoc false

  alias TreeDx.Files.PathPolicy

  @default_max_blob_bytes 10_485_760

  def read_repo(repo_id, params, principal) do
    with {:ok, scope} <- TreeDx.Capabilities.require_capability(principal, "files:read", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         :ok <- TreeDx.Capabilities.require_ref(scope, ref),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- TreeDx.Capabilities.require_paths(scope, [path]),
         :ok <- protected_allowed(path, truthy?(params["allowProtected"])),
         {:ok, blob} <- base_blob(repo, ref, path),
         :ok <- expected_hash(blob.contentHash, params["expectedContentHash"]) do
      audit("blob.read", principal, repo_id, nil, %{path: path, ref: ref})
      {:ok, %{blob: public_blob(blob)}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> normalize_not_found(other)
    end
  end

  def write_workspace(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         :ok <- encoding_base64(params["encoding"]),
         {:ok, content_base64} <- content_base64(params["contentBase64"]),
         :ok <- enforce_base64_size(content_base64),
         {:ok, content_hash} <- TreeDx.Store.hash_bytes_base64(content_base64),
         :ok <- expected_hash(content_hash, params["expectedContentHash"]),
         {:ok, current} <- current_blob_optional(ctx, path),
         :ok <- expected_sha(current && current.sha, params["expectedSha"]),
         {:ok, record} <-
           TreeDx.Store.put_workspace_file(%{
             workspaceId: workspace_id,
             path: path,
             op: "put",
             encoding: "base64",
             contentBase64: content_base64,
             expectedSha: params["expectedSha"],
             expectedContentHash: params["expectedContentHash"],
             baseSha: current && current.sha,
             contentType: content_type(path, params["contentType"], content_base64)
           }) do
      audit("blob.written", principal, ctx.repo["id"], workspace_id, %{
        path: path,
        contentHash: record["contentHash"]
      })

      {:ok, %{result: mutation_result(workspace_id, path, record)}}
    end
  end

  def delete_workspace(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:delete"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, current} <- current_blob(ctx, path),
         :ok <- expected_sha(current.sha, params["expectedSha"]),
         {:ok, record} <-
           TreeDx.Store.put_workspace_file(%{
             workspaceId: workspace_id,
             path: path,
             op: "delete",
             expectedSha: params["expectedSha"],
             baseSha: current.sha
           }) do
      audit("blob.deleted", principal, ctx.repo["id"], workspace_id, %{path: path})
      {:ok, %{result: mutation_result(workspace_id, path, record)}}
    end
  end

  def download_workspace(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, blob} <- current_blob(ctx, path),
         {:ok, bytes} <- Base.decode64(blob.contentBase64) do
      audit("blob.downloaded", principal, ctx.repo["id"], workspace_id, %{path: path})
      {:ok, Map.put(blob, :bytes, bytes)}
    else
      :error -> {:error, %{code: "internal_error", message: "Invalid blob encoding."}}
      other -> other
    end
  end

  def upload_workspace(workspace_id, params, bytes, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         :ok <- enforce_size(bytes),
         content_base64 <- Base.encode64(bytes),
         {:ok, content_hash} <- TreeDx.Store.hash_bytes_base64(content_base64),
         :ok <- expected_hash(content_hash, params["expectedContentHash"]),
         {:ok, current} <- current_blob_optional(ctx, path),
         :ok <- expected_sha(current && current.sha, params["expectedSha"]),
         {:ok, record} <-
           TreeDx.Store.put_workspace_file(%{
             workspaceId: workspace_id,
             path: path,
             op: "put",
             encoding: "base64",
             contentBase64: content_base64,
             expectedSha: params["expectedSha"],
             expectedContentHash: params["expectedContentHash"],
             baseSha: current && current.sha,
             contentType: content_type(path, params["contentType"], content_base64)
           }) do
      audit("blob.uploaded", principal, ctx.repo["id"], workspace_id, %{
        path: path,
        contentHash: record["contentHash"]
      })

      {:ok, %{result: mutation_result(workspace_id, path, record)}}
    end
  end

  def max_blob_bytes, do: env_int("TREEDX_MAX_BLOB_BYTES", @default_max_blob_bytes)

  defp context(workspace_id, principal, capability) do
    with {:ok, workspace} when is_map(workspace) <- TreeDx.Store.get_workspace(workspace_id),
         :ok <- same_actor(workspace, principal),
         {:ok, workspace, _current_scope} <-
           TreeDx.Workspaces.ensure_policy_current(workspace, principal, capability),
         {:ok, scope} <-
           TreeDx.Capabilities.require_capability(
             principal,
             capability,
             workspace["repositoryId"]
           ),
         :ok <- workspace_has_capability(workspace, capability),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(workspace["repositoryId"]) do
      {:ok, %{workspace: workspace, repo: repo, scope: scope, principal: principal}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      other -> other
    end
  end

  defp current_blob_optional(ctx, path) do
    case current_blob(ctx, path) do
      {:ok, blob} -> {:ok, blob}
      {:error, %{code: "not_found"}} -> {:ok, nil}
      other -> other
    end
  end

  defp current_blob(ctx, path) do
    with {:ok, overlay} <- TreeDx.Store.get_workspace_file(ctx.workspace["id"], path) do
      case overlay do
        %{"op" => "delete"} ->
          {:error, %{code: "not_found", message: "Blob not found."}}

        %{"op" => "put"} = record ->
          overlay_blob(record, path)

        nil ->
          base_blob(ctx.repo, ctx.workspace["baseCommitSha"], path)
      end
    end
  end

  defp overlay_blob(record, path) do
    with {:ok, %{"contentBase64" => content_base64}} <-
           TreeDx.Store.read_workspace_file_content(record),
         {:ok, content_hash} <- TreeDx.Store.hash_bytes_base64(content_base64 || "") do
      {:ok,
       %{
         path: path,
         encoding: "base64",
         contentBase64: content_base64,
         objectId: nil,
         sha: record["contentHash"] || content_hash,
         contentHash: record["contentHash"] || content_hash,
         byteLength: record["size"],
         contentType: record["contentType"] || content_type(path, nil, content_base64),
         source: "workspace"
       }}
    end
  end

  defp base_blob(repo, ref, path) do
    case TreeDx.Git.read_blob(TreeDx.RepositoryStorage.path!(repo), ref, path) do
      {:ok, blob} ->
        with {:ok, content_hash} <- TreeDx.Store.hash_bytes_base64(blob["contentBase64"]) do
          {:ok,
           %{
             path: path,
             encoding: "base64",
             contentBase64: blob["contentBase64"],
             objectId: blob["objectId"],
             sha: blob["objectId"],
             contentHash: content_hash,
             byteLength: blob["byteLength"],
             contentType: content_type(path, nil, blob["contentBase64"]),
             source: "base"
           }}
        end

      {:error, %{"code" => "not_found"}} ->
        {:error, %{code: "not_found", message: "Blob not found."}}

      other ->
        other
    end
  end

  defp public_blob(blob) do
    %{
      path: blob.path,
      encoding: "base64",
      contentBase64: blob.contentBase64,
      objectId: blob.objectId,
      sha: blob.sha,
      contentHash: blob.contentHash,
      byteLength: blob.byteLength,
      contentType: blob.contentType,
      source: blob.source
    }
  end

  defp mutation_result(workspace_id, path, record) do
    %{
      workspaceId: workspace_id,
      path: path,
      op: record["op"],
      encoding: record["encoding"],
      contentHash: record["contentHash"],
      byteLength: record["size"],
      contentType: record["contentType"]
    }
  end

  defp content_base64(content) when is_binary(content) do
    case Base.decode64(content) do
      {:ok, bytes} when is_binary(bytes) -> {:ok, content}
      :error -> {:error, %{code: "validation_error", message: "contentBase64 is invalid."}}
    end
  end

  defp content_base64(_),
    do: {:error, %{code: "validation_error", message: "contentBase64 is required."}}

  defp encoding_base64(nil), do: :ok
  defp encoding_base64("base64"), do: :ok

  defp encoding_base64(_),
    do: {:error, %{code: "validation_error", message: "encoding must be base64."}}

  defp expected_hash(_actual, nil), do: :ok
  defp expected_hash(_actual, ""), do: :ok
  defp expected_hash(actual, actual), do: :ok

  defp expected_hash(_actual, _expected),
    do: {:error, %{code: "conflict", message: "expectedContentHash does not match."}}

  defp expected_sha(_actual, nil), do: :ok
  defp expected_sha(_actual, ""), do: :ok
  defp expected_sha(actual, actual), do: :ok

  defp expected_sha(_actual, _expected),
    do: {:error, %{code: "conflict", message: "expectedSha does not match."}}

  defp enforce_base64_size(content_base64) do
    with {:ok, bytes} <- Base.decode64(content_base64) do
      enforce_size(bytes)
    else
      :error -> {:error, %{code: "validation_error", message: "contentBase64 is invalid."}}
    end
  end

  defp enforce_size(bytes) do
    if byte_size(bytes) <= max_blob_bytes() do
      :ok
    else
      {:error, %{code: "payload_too_large", message: "Blob exceeds TREEDX_MAX_BLOB_BYTES."}}
    end
  end

  defp protected_allowed(_path, true), do: :ok

  defp protected_allowed(path, _allow_protected) do
    if PathPolicy.protected?(path) do
      {:error,
       %{
         code: "permission_denied",
         message: "Permission denied.",
         details: %{path: path, protected: true}
       }}
    else
      :ok
    end
  end

  defp content_type(_path, explicit, _content_base64)
       when is_binary(explicit) and explicit != "",
       do: explicit

  defp content_type(path, _explicit, content_base64) do
    ext = path |> Path.extname() |> String.downcase()

    case ext do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      ".json" -> "application/json"
      ".txt" -> "text/plain; charset=utf-8"
      ".md" -> "text/markdown; charset=utf-8"
      _ -> content_type_from_bytes(content_base64)
    end
  end

  defp content_type_from_bytes(content_base64) do
    case Base.decode64(content_base64 || "") do
      {:ok, bytes} ->
        if String.valid?(bytes), do: "text/plain; charset=utf-8", else: "application/octet-stream"

      :error ->
        "application/octet-stream"
    end
  end

  defp same_actor(workspace, principal) do
    if workspace["actorId"] == actor_id(principal) do
      :ok
    else
      {:error, %{code: "permission_denied", message: "Permission denied."}}
    end
  end

  defp workspace_has_capability(workspace, capability) do
    if capability in (workspace["capabilities"] || []) do
      :ok
    else
      {:error,
       %{
         code: "permission_denied",
         message: "Permission denied.",
         details: %{capability: capability}
       }}
    end
  end

  defp audit(event, principal, repo_id, workspace_id, data) do
    TreeDx.Audit.append(event, %{
      actor_id: actor_id(principal),
      tenant_id: tenant_id(principal),
      repo_id: repo_id,
      workspace_id: workspace_id,
      operation: event,
      status: "ok",
      data: data
    })
  end

  defp normalize_not_found({:error, %{"code" => "not_found"}}),
    do: {:error, %{code: "not_found", message: "Blob not found."}}

  defp normalize_not_found(other), do: other

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp actor_id(principal),
    do: principal["actorId"] || principal[:actorId] || principal[:actor_id]

  defp tenant_id(principal),
    do: principal["tenantId"] || principal[:tenantId] || principal[:tenant_id]
end
