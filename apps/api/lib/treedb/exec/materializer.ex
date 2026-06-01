defmodule TreeDb.Exec.Materializer do
  @moduledoc false

  def materialize(ctx) do
    root = Path.join(ctx.workspace["materializedPath"], "shell")
    File.rm_rf!(root)
    File.mkdir_p!(root)

    with {:ok, base_entries} <-
           TreeDb.Git.list_tree_recursive(
             ctx.repo["localPath"],
             ctx.workspace["baseCommitSha"],
             nil
           ),
         :ok <- materialize_base(ctx, root, base_entries),
         {:ok, overlays} <- TreeDb.Store.list_workspace_files(ctx.workspace["id"]),
         :ok <- materialize_overlays(ctx, root, overlays) do
      {:ok, root}
    end
  end

  def snapshot(root) do
    if File.dir?(root) do
      root
      |> list_files()
      |> Map.new(fn absolute ->
        path = Path.relative_to(absolute, root)
        {path, %{hash: hash_file(absolute), absolute: absolute}}
      end)
    else
      %{}
    end
  end

  def changed_paths(before, after_snapshot) do
    (Map.keys(before) ++ Map.keys(after_snapshot))
    |> Enum.uniq()
    |> Enum.filter(fn path -> before[path] != after_snapshot[path] end)
    |> Enum.sort()
  end

  defp materialize_base(ctx, root, entries) do
    entries
    |> Enum.filter(&(&1["kind"] == "blob"))
    |> Enum.filter(&path_allowed?(ctx.workspace, &1["path"]))
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      case TreeDb.Git.read_blob(
             ctx.repo["localPath"],
             ctx.workspace["baseCommitSha"],
             entry["path"]
           ) do
        {:ok, blob} ->
          write_base64(root, entry["path"], blob["contentBase64"])
          {:cont, :ok}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp materialize_overlays(ctx, root, overlays) do
    overlays
    |> Enum.filter(&path_allowed?(ctx.workspace, &1["path"]))
    |> Enum.reduce_while(:ok, fn record, :ok ->
      target = safe_join!(root, record["path"])

      case record["op"] do
        "delete" ->
          File.rm(target)
          {:cont, :ok}

        "put" ->
          case TreeDb.Store.read_workspace_file_content(record) do
            {:ok, %{"contentBase64" => content}} ->
              write_base64(root, record["path"], content)
              {:cont, :ok}

            {:error, error} ->
              {:halt, {:error, error}}
          end
      end
    end)
  end

  defp write_base64(root, path, content_base64) do
    {:ok, content} = Base.decode64(content_base64)
    target = safe_join!(root, path)
    File.mkdir_p!(Path.dirname(target))
    File.write!(target, content)
  end

  defp path_allowed?(workspace, path) do
    TreeDb.Capabilities.require_paths(workspace["effectiveScope"] || %{}, [path]) == :ok
  end

  defp list_files(root) do
    root
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      path = Path.join(root, entry)

      cond do
        File.dir?(path) -> list_files(path)
        File.regular?(path) -> [path]
        true -> []
      end
    end)
  end

  defp hash_file(path),
    do: :crypto.hash(:blake2s, File.read!(path)) |> Base.encode16(case: :lower)

  defp safe_join!(root, path) do
    target = Path.expand(Path.join(root, path))
    root = Path.expand(root)

    if target == root or String.starts_with?(target, root <> "/") do
      target
    else
      raise ArgumentError, "path escaped workspace"
    end
  end
end
