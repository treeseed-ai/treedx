defmodule TreeDx.Files.WorkspaceFiles do
  @moduledoc false

  alias TreeDx.Files.Overlay

  def current(ctx, path) do
    with {:ok, state} <- existing(ctx, path) do
      {:ok,
       %{
         path: state.path,
         encoding: "utf8",
         content: state.content,
         sha: state.sha,
         source: to_string(state.source),
         stat: state.stat
       }}
    end
  end

  def existing(ctx, path) do
    with {:ok, state} <- state(ctx, path) do
      if state.source == :missing do
        {:error, %{code: "not_found", message: "File not found."}}
      else
        {:ok, state}
      end
    end
  end

  def state(ctx, path) do
    with {:ok, overlay} <- TreeDx.Store.get_workspace_file(ctx.workspace["id"], path) do
      case overlay do
        %{"op" => "delete", "baseSha" => base_sha} ->
          {:ok, missing_state(path, base_sha, overlay)}

        %{"op" => "put"} = record ->
          with {:ok, content} <- Overlay.read_overlay(record) do
            {:ok,
             %{
               source: :overlay,
               path: path,
               content: content,
               sha: record["contentHash"],
               base_sha: record["baseSha"],
               stat: %{size: record["size"], mtime: record["updatedAt"]},
               record: record
             }}
          end

        nil ->
          case base(ctx, path) do
            {:ok, file} ->
              {:ok,
               %{
                 source: :base,
                 path: path,
                 content: file.content,
                 sha: file.sha,
                 base_sha: file.sha,
                 stat: file.stat,
                 record: nil
               }}

            {:error, %{code: "not_found"}} ->
              {:ok, missing_state(path, nil, nil)}

            other ->
              other
          end
      end
    end
  end

  def base(ctx, path) do
    case TreeDx.Git.read_blob(
           TreeDx.RepositoryStorage.path!(ctx.repo),
           ctx.workspace["baseCommitSha"],
           path
         ) do
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

  def tree(ctx, path) do
    case TreeDx.Git.list_tree(
           TreeDx.RepositoryStorage.path!(ctx.repo),
           ctx.workspace["baseCommitSha"],
           empty_to_nil(path)
         ) do
      {:ok, entries} -> {:ok, entries}
      {:error, %{"code" => "not_found"}} -> {:ok, []}
      other -> other
    end
  end

  def text_files(ctx, root) do
    with {:ok, base_entries} <- list_base_tree_recursive(ctx, root),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(ctx.workspace["id"]) do
      base_files =
        base_entries
        |> Enum.filter(&(&1["kind"] == "blob"))
        |> Enum.map(fn entry ->
          case base(ctx, entry["path"]) do
            {:ok, file} -> {entry["path"], file.content, "base"}
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Map.new(fn {path, content, source} -> {path, {content, source}} end)

      files =
        Enum.reduce(overlays, base_files, fn record, acc ->
          cond do
            !under_path?(record["path"], root) -> acc
            record["op"] == "delete" -> Map.delete(acc, record["path"])
            true -> put_overlay_content(acc, record)
          end
        end)

      {:ok, Enum.map(files, fn {path, {content, source}} -> {path, content, source} end)}
    end
  end

  def put(ctx, path, content, expected_sha, base_sha) do
    TreeDx.Store.put_workspace_file(%{
      workspaceId: ctx.workspace["id"],
      path: path,
      op: "put",
      encoding: "utf8",
      contentBase64: Base.encode64(content),
      expectedSha: expected_sha,
      baseSha: base_sha
    })
  end

  def merge_tree(entries, overlays, path, include_deleted) do
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
    |> Enum.reduce(base, &merge_overlay(&1, &2, base, include_deleted))
    |> Map.values()
    |> Enum.sort_by(& &1.path)
  end

  defp missing_state(path, base_sha, record) do
    %{
      source: :missing,
      path: path,
      content: nil,
      sha: nil,
      base_sha: base_sha,
      stat: nil,
      record: record
    }
  end

  defp list_base_tree_recursive(ctx, root) do
    case TreeDx.Git.list_tree_recursive(
           TreeDx.RepositoryStorage.path!(ctx.repo),
           ctx.workspace["baseCommitSha"],
           empty_to_nil(root)
         ) do
      {:ok, entries} -> {:ok, entries}
      {:error, %{"code" => "not_found"}} -> {:ok, []}
      {:error, %{code: "not_found"}} -> {:ok, []}
      other -> other
    end
  end

  defp put_overlay_content(acc, record) do
    case Overlay.read_overlay(record) do
      {:ok, content} -> Map.put(acc, record["path"], {content, "overlay"})
      _ -> acc
    end
  end

  defp merge_overlay(record, acc, base, include_deleted) do
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
  end

  defp direct_child?(child, ""), do: !String.contains?(child, "/")

  defp direct_child?(child, parent),
    do:
      String.starts_with?(child, parent <> "/") and
        !String.contains?(String.replace_prefix(child, parent <> "/", ""), "/")

  defp under_path?(_path, ""), do: true
  defp under_path?(path, root), do: path == root or String.starts_with?(path, root <> "/")
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
