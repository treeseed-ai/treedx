defmodule TreeDx.Files do
  @moduledoc false

  alias TreeDx.Files.{Diff, Overlay, Patch, PathPolicy, Search, WorkspaceFiles}
  alias TreeDx.Runtime.Pool

  @default_search_limit 20
  @max_search_limit 50
  @default_max_file_bytes 1_048_576

  def tree(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, path} <- PathPolicy.normalize(params["path"], allow_empty: true),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, entries} <- WorkspaceFiles.tree(ctx, path),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(workspace_id) do
      include_deleted = truthy?(params["includeDeleted"])
      merged = WorkspaceFiles.merge_tree(entries, overlays, path, include_deleted)
      audit("file.tree_listed", ctx, %{workspaceId: workspace_id, path: path})
      {:ok, %{workspaceId: workspace_id, path: path, entries: merged}}
    end
  end

  def read(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, file} <- WorkspaceFiles.current(ctx, path) do
      audit("file.read", ctx, %{workspaceId: workspace_id, path: path})
      {:ok, Map.delete(file, :contentBase64)}
    end
  end

  def write(workspace_id, params, principal) do
    Pool.run(:workspace_mutation, fn -> do_write(workspace_id, params, principal) end)
  end

  defp do_write(workspace_id, params, principal) do
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, content} <- utf8_content(params["content"]),
         :ok <- enforce_size(content),
         {:ok, state} <- WorkspaceFiles.state(ctx, path),
         :ok <- expected_sha_value(state.sha, params["expectedSha"]),
         {:ok, record} <-
           WorkspaceFiles.put(ctx, path, content, params["expectedSha"], state.base_sha) do
      audit("file.written", ctx, %{
        workspaceId: workspace_id,
        path: path,
        contentHash: record["contentHash"]
      })

      {:ok,
       %{
         file: %{
           path: path,
           encoding: "utf8",
           sha: record["contentHash"],
           size: record["size"],
           source: "overlay"
         }
       }}
    end
  end

  def patch(workspace_id, params, principal) do
    Pool.run(:workspace_mutation, fn -> do_patch(workspace_id, params, principal) end)
  end

  defp do_patch(workspace_id, params, principal) do
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, state} <- WorkspaceFiles.existing(ctx, path),
         :ok <- expected_sha_value(state.sha, params["expectedSha"]),
         {:ok, patched} <- Patch.apply(state.content, params["patch"], path),
         :ok <- enforce_size(patched),
         {:ok, record} <-
           WorkspaceFiles.put(ctx, path, patched, params["expectedSha"], state.base_sha) do
      audit("file.patched", ctx, %{
        workspaceId: workspace_id,
        path: path,
        contentHash: record["contentHash"]
      })

      {:ok,
       %{
         file: %{
           path: path,
           encoding: "utf8",
           sha: record["contentHash"],
           size: record["size"],
           source: "overlay"
         }
       }}
    end
  end

  def delete(workspace_id, params, principal) do
    Pool.run(:workspace_mutation, fn -> do_delete(workspace_id, params, principal) end)
  end

  defp do_delete(workspace_id, params, principal) do
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:delete"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, state} <- WorkspaceFiles.existing(ctx, path),
         :ok <- expected_sha_value(state.sha, params["expectedSha"]),
         {:ok, _record} <-
           TreeDx.Store.put_workspace_file(%{
             workspaceId: workspace_id,
             path: path,
             op: "delete",
             expectedSha: params["expectedSha"],
             baseSha: state.base_sha
           }) do
      audit("file.deleted", ctx, %{workspaceId: workspace_id, path: path})
      {:ok, %{path: path, status: "deleted"}}
    end
  end

  def search(workspace_id, params, principal) do
    query = params["query"] || ""
    limit = params["limit"] || @default_search_limit
    path_param = params["path"] || ""

    with {:ok, ctx} <- context(workspace_id, principal, "files:search"),
         :ok <- validate_query(query),
         {:ok, path} <- PathPolicy.normalize(path_param, allow_empty: true),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, files} <- WorkspaceFiles.text_files(ctx, path) do
      limit = limit |> coerce_int(@default_search_limit) |> min(@max_search_limit)
      results = Search.find(files, query, limit, truthy?(params["caseSensitive"]))
      truncated = length(results) > limit
      audit("file.searched", ctx, %{workspaceId: workspace_id, path: path})

      {:ok,
       %{
         workspaceId: workspace_id,
         query: query,
         results: Enum.take(results, limit),
         truncated: truncated
       }}
    end
  end

  def status(workspace_id, _params, principal) do
    Pool.run(:workspace_mutation, fn -> do_status(workspace_id, principal) end)
  end

  defp do_status(workspace_id, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(workspace_id) do
      changes = Enum.map(overlays, &status_entry(ctx, &1))
      audit("workspace.status_viewed", ctx, %{workspaceId: workspace_id})
      {:ok, %{workspaceId: workspace_id, status: ctx.workspace["status"], changes: changes}}
    end
  end

  def diff(workspace_id, _params, principal) do
    Pool.run(:workspace_mutation, fn -> do_diff(workspace_id, principal) end)
  end

  defp do_diff(workspace_id, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "git:diff"),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(workspace_id) do
      diffs =
        overlays
        |> Enum.map(&diff_entry(ctx, &1))
        |> Enum.join("\n")

      changed_paths = Enum.map(overlays, & &1["path"])

      audit("workspace.diff_viewed", ctx, %{
        workspaceId: workspace_id,
        changedPaths: changed_paths
      })

      {:ok, %{workspaceId: workspace_id, diff: diffs, changedPaths: changed_paths}}
    end
  end

  def commit(workspace_id, params, principal) do
    Pool.run(:workspace_mutation, fn -> do_commit(workspace_id, params, principal) end)
  end

  defp do_commit(workspace_id, params, principal) do
    with {:ok, ctx} <- writable_context(workspace_id, principal, "git:commit"),
         :ok <- require_branch(ctx.workspace),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(workspace_id),
         :ok <- require_changes(overlays),
         {:ok, changes} <- commit_changes(overlays),
         {:ok, result} <-
           TreeDx.Git.commit_overlay(%{
             repoPath: TreeDx.RepositoryStorage.path!(ctx.repo),
             baseCommitSha: ctx.workspace["baseCommitSha"],
             branchName: ctx.workspace["branchName"],
             message: params["message"] || "Update repository file through TreeDX",
             authorName: get_in(params, ["author", "name"]) || "TreeDX Agent",
             authorEmail: get_in(params, ["author", "email"]) || "agent@example.invalid",
             changes: changes
           }),
         {:ok, committed} <-
           TreeDx.Store.mark_workspace_committed(%{
             workspaceId: workspace_id,
             commitSha: result["commitSha"]
           }) do
      audit("workspace.committed", ctx, %{
        workspaceId: workspace_id,
        changedPaths: result["changedPaths"],
        commitSha: result["commitSha"]
      })

      {:ok,
       %{
         repoId: ctx.repo["id"],
         workspaceId: workspace_id,
         branchName: committed["branchName"],
         commitSha: result["commitSha"],
         changedPaths: result["changedPaths"],
         status: committed["status"]
       }}
    end
  end

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

  defp writable_context(workspace_id, principal, capability) do
    with {:ok, ctx} <- context(workspace_id, principal, capability),
         :ok <- workspace_writable(ctx.workspace) do
      {:ok, ctx}
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

  defp workspace_writable(workspace) do
    cond do
      workspace["mode"] != "writable" ->
        {:error, %{code: "permission_denied", message: "Workspace is read-only."}}

      workspace["status"] != "ready" ->
        {:error, %{code: "conflict", message: "Workspace is not writable."}}

      DateTime.compare(parse_time!(workspace["expiresAt"]), DateTime.utc_now()) != :gt ->
        {:error, %{code: "conflict", message: "Workspace has expired."}}

      is_nil(workspace["leaseId"]) ->
        {:error, %{code: "conflict", message: "Workspace has no active writable lease."}}

      true ->
        :ok
    end
  end

  defp expected_sha_value(_actual, nil), do: :ok
  defp expected_sha_value(_actual, ""), do: :ok
  defp expected_sha_value(actual, actual), do: :ok

  defp expected_sha_value(_actual, _expected),
    do: {:error, %{code: "conflict", message: "expectedSha does not match."}}

  defp status_entry(ctx, record) do
    base = WorkspaceFiles.base(ctx, record["path"])
    binary = record["encoding"] == "base64"

    status =
      if record["op"] == "delete",
        do: "deleted",
        else: if(match?({:ok, _}, base), do: "modified", else: "added")

    base_sha =
      case base do
        {:ok, file} -> file.sha
        _ -> nil
      end

    %{
      path: record["path"],
      status: status,
      baseSha: base_sha,
      contentHash: record["contentHash"],
      encoding: record["encoding"],
      binary: binary,
      size: record["size"],
      updatedAt: record["updatedAt"]
    }
  end

  defp diff_entry(ctx, %{"encoding" => "base64"} = record) do
    base = WorkspaceFiles.base(ctx, record["path"])

    status =
      cond do
        record["op"] == "delete" -> "deleted"
        match?({:ok, _}, base) -> "modified"
        true -> "added"
      end

    "Binary file #{record["path"]} #{status}"
  end

  defp diff_entry(ctx, %{"op" => "delete"} = record) do
    old =
      case WorkspaceFiles.base(ctx, record["path"]) do
        {:ok, file} -> file.content
        _ -> ""
      end

    Diff.unified(record["path"], old, "")
  end

  defp diff_entry(ctx, record) do
    old =
      case WorkspaceFiles.base(ctx, record["path"]) do
        {:ok, file} -> file.content
        _ -> ""
      end

    new =
      case Overlay.read_overlay(record) do
        {:ok, content} -> content
        _ -> ""
      end

    Diff.unified(record["path"], old, new)
  end

  defp commit_changes(overlays) do
    overlays
    |> Enum.map(fn
      %{"op" => "delete"} = record ->
        {:ok, %{path: record["path"], op: "delete", expectedSha: record["expectedSha"]}}

      %{"op" => "put"} = record ->
        case TreeDx.Store.read_workspace_file_content(record) do
          {:ok, %{"contentBase64" => content}} ->
            {:ok,
             %{
               path: record["path"],
               op: "put",
               contentBase64: content,
               expectedSha: record["expectedSha"]
             }}

          other ->
            other
        end
    end)
    |> collect_ok()
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp utf8_content(content) when is_binary(content) do
    if String.valid?(content),
      do: {:ok, content},
      else: {:error, %{code: "unsupported_media_type", message: "content must be UTF-8."}}
  end

  defp utf8_content(_), do: {:error, %{code: "validation_error", message: "content is required."}}

  defp enforce_size(content) do
    if byte_size(content) <= max_file_bytes() do
      :ok
    else
      {:error, %{code: "payload_too_large", message: "File exceeds TREEDX_MAX_FILE_BYTES."}}
    end
  end

  defp max_file_bytes do
    System.get_env("TREEDX_MAX_FILE_BYTES", "#{@default_max_file_bytes}") |> String.to_integer()
  end

  defp validate_query(query) do
    cond do
      !is_binary(query) or query == "" ->
        {:error, %{code: "validation_error", message: "query is required."}}

      String.length(query) > 200 ->
        {:error, %{code: "validation_error", message: "query is too long."}}

      true ->
        :ok
    end
  end

  defp require_branch(%{"branchName" => branch}) when is_binary(branch) and branch != "", do: :ok

  defp require_branch(_),
    do: {:error, %{code: "validation_error", message: "branchName is required."}}

  defp require_changes([]),
    do: {:error, %{code: "validation_error", message: "no workspace changes to commit."}}

  defp require_changes(_), do: :ok

  defp coerce_int(value, _default) when is_integer(value), do: value

  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> default
    end
  end

  defp coerce_int(_value, default), do: default
  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp parse_time!(value) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end

  defp actor_id(principal),
    do: principal["actorId"] || principal[:actorId] || principal[:actor_id]

  defp tenant_id(principal),
    do: principal["tenantId"] || principal[:tenantId] || principal[:tenant_id]

  defp audit(event_type, ctx, data) do
    TreeDx.Audit.append(event_type, %{
      actor_id: actor_id(ctx.principal),
      tenant_id: tenant_id(ctx.principal),
      repo_id: ctx.repo["id"],
      data: data
    })
  end
end
