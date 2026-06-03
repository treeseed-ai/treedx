defmodule TreeDb.Files do
  @moduledoc false

  alias TreeDb.Files.{Diff, Overlay, Patch, PathPolicy, Search}

  @default_search_limit 20
  @max_search_limit 50
  @default_max_file_bytes 1_048_576

  def tree(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, path} <- PathPolicy.normalize(params["path"], allow_empty: true),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, entries} <- base_tree(ctx, path),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(workspace_id) do
      include_deleted = truthy?(params["includeDeleted"])
      merged = merge_tree_entries(entries, overlays, path, include_deleted)
      audit("file.tree_listed", ctx, %{workspaceId: workspace_id, path: path})
      {:ok, %{workspaceId: workspace_id, path: path, entries: merged}}
    end
  end

  def read(workspace_id, params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, file} <- current_file(ctx, path) do
      audit("file.read", ctx, %{workspaceId: workspace_id, path: path})
      {:ok, Map.delete(file, :contentBase64)}
    end
  end

  def write(workspace_id, params, principal) do
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, content} <- utf8_content(params["content"]),
         :ok <- enforce_size(content),
         :ok <- expected_sha(ctx, path, params["expectedSha"]),
         {:ok, base_sha} <- base_sha(ctx, path),
         {:ok, record} <- put_overlay(ctx, path, content, params["expectedSha"], base_sha) do
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
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:write"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, file} <- current_file(ctx, path),
         :ok <- expected_sha_value(file.sha, params["expectedSha"]),
         {:ok, patched} <- Patch.apply(file.content, params["patch"], path),
         :ok <- enforce_size(patched),
         {:ok, base_sha} <- base_sha(ctx, path),
         {:ok, record} <- put_overlay(ctx, path, patched, params["expectedSha"], base_sha) do
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
    with {:ok, ctx} <- writable_context(workspace_id, principal, "files:delete"),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(ctx.workspace, path, truthy?(params["allowProtected"])),
         {:ok, file} <- current_file(ctx, path),
         :ok <- expected_sha_value(file.sha, params["expectedSha"]),
         {:ok, base_sha} <- base_sha(ctx, path),
         {:ok, _record} <-
           TreeDb.Store.put_workspace_file(%{
             workspaceId: workspace_id,
             path: path,
             op: "delete",
             expectedSha: params["expectedSha"],
             baseSha: base_sha
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
         {:ok, files} <- workspace_text_files(ctx, path) do
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
    with {:ok, ctx} <- context(workspace_id, principal, "files:read"),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(workspace_id) do
      changes = Enum.map(overlays, &status_entry(ctx, &1))
      audit("workspace.status_viewed", ctx, %{workspaceId: workspace_id})
      {:ok, %{workspaceId: workspace_id, status: ctx.workspace["status"], changes: changes}}
    end
  end

  def diff(workspace_id, _params, principal) do
    with {:ok, ctx} <- context(workspace_id, principal, "git:diff"),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(workspace_id) do
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
    with {:ok, ctx} <- writable_context(workspace_id, principal, "git:commit"),
         :ok <- require_branch(ctx.workspace),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(workspace_id),
         :ok <- require_changes(overlays),
         {:ok, changes} <- commit_changes(overlays),
         {:ok, result} <-
           TreeDb.Git.commit_overlay(%{
             repoPath: ctx.repo["localPath"],
             baseCommitSha: ctx.workspace["baseCommitSha"],
             branchName: ctx.workspace["branchName"],
             message: params["message"] || "Update repository file through TreeDB",
             authorName: get_in(params, ["author", "name"]) || "TreeDB Agent",
             authorEmail: get_in(params, ["author", "email"]) || "agent@example.invalid",
             changes: changes
           }),
         {:ok, committed} <-
           TreeDb.Store.mark_workspace_committed(%{
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
    with {:ok, workspace} when is_map(workspace) <- TreeDb.Store.get_workspace(workspace_id),
         :ok <- same_actor(workspace, principal),
         {:ok, workspace, _current_scope} <-
           TreeDb.Workspaces.ensure_policy_current(workspace, principal, capability),
         {:ok, scope} <-
           TreeDb.Capabilities.require_capability(
             principal,
             capability,
             workspace["repositoryId"]
           ),
         :ok <- workspace_has_capability(workspace, capability),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(workspace["repositoryId"]) do
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

  defp current_file(ctx, path) do
    with {:ok, overlay} <- TreeDb.Store.get_workspace_file(ctx.workspace["id"], path) do
      case overlay do
        %{"op" => "delete"} ->
          {:error, %{code: "not_found", message: "File not found."}}

        %{"op" => "put"} = record ->
          with {:ok, content} <- Overlay.read_overlay(record) do
            {:ok,
             %{
               path: path,
               encoding: "utf8",
               content: content,
               sha: record["contentHash"],
               source: "overlay",
               stat: %{size: record["size"], mtime: record["updatedAt"]}
             }}
          end

        nil ->
          base_file(ctx, path)
      end
    end
  end

  defp base_file(ctx, path) do
    case TreeDb.Git.read_blob(ctx.repo["localPath"], ctx.workspace["baseCommitSha"], path) do
      {:ok, blob} ->
        with {:ok, bytes} <- Base.decode64(blob["contentBase64"]),
             {:ok, content} <- Overlay.utf8(bytes) do
          {:ok,
           %{
             path: path,
             encoding: "utf8",
             content: content,
             sha: blob["objectId"],
             source: "base",
             stat: %{size: blob["byteLength"], mtime: nil}
           }}
        else
          :error ->
            {:error, %{code: "unsupported_media_type", message: "File is not valid UTF-8."}}

          other ->
            other
        end

      {:error, %{"code" => "not_found"}} ->
        {:error, %{code: "not_found", message: "File not found."}}

      other ->
        other
    end
  end

  defp base_tree(ctx, path) do
    case TreeDb.Git.list_tree(
           ctx.repo["localPath"],
           ctx.workspace["baseCommitSha"],
           empty_to_nil(path)
         ) do
      {:ok, entries} -> {:ok, entries}
      {:error, %{"code" => "not_found"}} -> {:ok, []}
      other -> other
    end
  end

  defp workspace_text_files(ctx, root) do
    with {:ok, base_entries} <-
           TreeDb.Git.list_tree_recursive(
             ctx.repo["localPath"],
             ctx.workspace["baseCommitSha"],
             empty_to_nil(root)
           ),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(ctx.workspace["id"]) do
      base_files =
        base_entries
        |> Enum.filter(&(&1["kind"] == "blob"))
        |> Enum.map(fn entry ->
          case base_file(ctx, entry["path"]) do
            {:ok, file} -> {entry["path"], file.content, "base"}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new(fn {path, content, source} -> {path, {content, source}} end)

      files =
        Enum.reduce(overlays, base_files, fn record, acc ->
          cond do
            !under_path?(record["path"], root) ->
              acc

            record["op"] == "delete" ->
              Map.delete(acc, record["path"])

            true ->
              case Overlay.read_overlay(record) do
                {:ok, content} -> Map.put(acc, record["path"], {content, "overlay"})
                _ -> acc
              end
          end
        end)

      {:ok, Enum.map(files, fn {path, {content, source}} -> {path, content, source} end)}
    end
  end

  defp put_overlay(ctx, path, content, expected_sha, base_sha) do
    TreeDb.Store.put_workspace_file(%{
      workspaceId: ctx.workspace["id"],
      path: path,
      op: "put",
      encoding: "utf8",
      contentBase64: Base.encode64(content),
      expectedSha: expected_sha,
      baseSha: base_sha
    })
  end

  defp expected_sha(ctx, path, expected) do
    case current_file(ctx, path) do
      {:ok, file} ->
        expected_sha_value(file.sha, expected)

      {:error, %{code: "not_found"}} ->
        if expected in [nil, ""],
          do: :ok,
          else: {:error, %{code: "conflict", message: "expectedSha does not match."}}

      other ->
        other
    end
  end

  defp expected_sha_value(_actual, nil), do: :ok
  defp expected_sha_value(_actual, ""), do: :ok
  defp expected_sha_value(actual, actual), do: :ok

  defp expected_sha_value(_actual, _expected),
    do: {:error, %{code: "conflict", message: "expectedSha does not match."}}

  defp base_sha(ctx, path) do
    case base_file(ctx, path) do
      {:ok, file} -> {:ok, file.sha}
      {:error, %{code: "not_found"}} -> {:ok, nil}
      other -> other
    end
  end

  defp merge_tree_entries(entries, overlays, path, include_deleted) do
    base =
      Map.new(entries, fn entry ->
        {entry["path"],
         %{
           path: entry["path"],
           name: entry["name"],
           kind: entry["kind"],
           status: "base",
           source: "base",
           objectId: entry["objectId"],
           contentHash: nil
         }}
      end)

    overlays
    |> Enum.filter(&direct_child?(&1["path"], path))
    |> Enum.reduce(base, fn record, acc ->
      if record["op"] == "delete" and !include_deleted do
        Map.delete(acc, record["path"])
      else
        Map.put(acc, record["path"], %{
          path: record["path"],
          name: Path.basename(record["path"]),
          kind: "blob",
          status:
            if(record["op"] == "delete",
              do: "deleted",
              else: if(Map.has_key?(base, record["path"]), do: "modified", else: "added")
            ),
          source: "overlay",
          objectId: Map.get(base[record["path"]] || %{}, :objectId),
          contentHash: record["contentHash"]
        })
      end
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.path)
  end

  defp status_entry(ctx, record) do
    base = base_file(ctx, record["path"])
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
    base = base_file(ctx, record["path"])

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
      case base_file(ctx, record["path"]) do
        {:ok, file} -> file.content
        _ -> ""
      end

    Diff.unified(record["path"], old, "")
  end

  defp diff_entry(ctx, record) do
    old =
      case base_file(ctx, record["path"]) do
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
        case TreeDb.Store.read_workspace_file_content(record) do
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
      {:error, %{code: "payload_too_large", message: "File exceeds TREEDB_MAX_FILE_BYTES."}}
    end
  end

  defp max_file_bytes do
    System.get_env("TREEDB_MAX_FILE_BYTES", "#{@default_max_file_bytes}") |> String.to_integer()
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

  defp direct_child?(child, ""), do: !String.contains?(child, "/")

  defp direct_child?(child, parent),
    do:
      String.starts_with?(child, parent <> "/") and
        !String.contains?(String.replace_prefix(child, parent <> "/", ""), "/")

  defp under_path?(_path, ""), do: true
  defp under_path?(path, root), do: path == root or String.starts_with?(path, root <> "/")
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
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
    TreeDb.Audit.append(event_type, %{
      actor_id: actor_id(ctx.principal),
      tenant_id: tenant_id(ctx.principal),
      repo_id: ctx.repo["id"],
      data: data
    })
  end
end
