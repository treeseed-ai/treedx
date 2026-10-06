defmodule TreeDx.Graph.Builder do
  @moduledoc false

  alias TreeDx.Files.PathPolicy
  alias TreeDx.RepositoryQuery.PathMatch

  @extensions ~w(.md .mdx .txt)

  def build_input(ctx, params, previous_manifest, previous_index \\ nil) do
    with {:ok, patterns} <-
           PathMatch.normalize_patterns(expand_logical_content_paths(params["paths"])),
         {:ok, entries} <-
           TreeDx.Git.list_tree_recursive(TreeDx.RepositoryStorage.path!(ctx.repo), ctx.ref, nil),
         {:ok, documents, loaded_count, reused_count} <-
           documents(ctx, entries, patterns, params, previous_index) do
      {:ok,
       %{
         repoId: ctx.repo["id"],
         refName: ctx.ref,
         commitSha: ctx.resolved_ref,
         documents: documents,
         previousManifest: previous_manifest,
         previousDocuments: previous_documents(previous_index),
         loadedPathCount: loaded_count,
         reusedPathCount: reused_count
       }}
    end
  end

  defp expand_logical_content_paths(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(fn
      path when is_binary(path) ->
        if Path.extname(path) == "" and not String.ends_with?(path, "*") do
          [path, path <> ".md", path <> ".mdx"]
        else
          [path]
        end

      path ->
        [path]
    end)
    |> Enum.uniq()
  end

  defp expand_logical_content_paths(paths), do: paths

  defp documents(ctx, entries, patterns, params, previous_index) do
    previous = previous_by_path(previous_index)

    entries
    |> Enum.filter(&(&1["kind"] == "blob"))
    |> Enum.filter(&(Path.extname(&1["path"]) in @extensions))
    |> Enum.filter(&allowed?(&1["path"], ctx.scope, patterns, params))
    |> Enum.map(&document(ctx, &1, previous))
    |> collect_ok([], 0, 0)
  end

  defp document(ctx, entry, previous) do
    object_id = entry["objectId"]

    case previous[entry["path"]] do
      %{"objectId" => ^object_id} = document ->
        {:ok, cached_document(entry, document), :reused}

      _ ->
        load_document(ctx, entry)
    end
  end

  defp load_document(ctx, entry) do
    with {:ok, blob} <-
           TreeDx.Git.read_blob(TreeDx.RepositoryStorage.path!(ctx.repo), ctx.ref, entry["path"]),
         {:ok, bytes} <- Base.decode64(blob["contentBase64"]),
         true <- String.valid?(bytes) do
      {:ok,
       %{
         path: entry["path"],
         objectId: entry["objectId"],
         size: entry["size"] || blob["byteLength"],
         content: IO.iodata_to_binary(bytes)
       }, :loaded}
    else
      false -> {:ok, nil, :loaded}
      :error -> {:ok, nil, :loaded}
      other -> other
    end
  end

  defp cached_document(entry, document) do
    frontmatter = Jason.encode!(document["frontmatter"] || %{})

    %{
      path: entry["path"],
      objectId: entry["objectId"],
      size: entry["size"] || document["size"] || 0,
      content: "---\n#{frontmatter}\n---\n#{document["body"] || ""}"
    }
  end

  defp previous_by_path(%{"documents" => documents}) when is_list(documents),
    do: Map.new(documents, &{&1["path"], &1})

  defp previous_by_path(_previous_index), do: %{}

  defp previous_documents(%{"documents" => documents}) when is_list(documents), do: documents
  defp previous_documents(_previous_index), do: []

  defp allowed?(path, scope, patterns, params) do
    PathMatch.match_any?(patterns, path) and
      (truthy?(params["allowProtected"]) or !PathPolicy.protected?(path)) and
      match?(:ok, TreeDx.Capabilities.require_paths(scope, [path]))
  end

  defp collect_ok([], items, loaded, reused),
    do: {:ok, Enum.reverse(items), loaded, reused}

  defp collect_ok([result | rest], items, loaded, reused) do
    case result do
      {:ok, nil, :loaded} -> collect_ok(rest, items, loaded + 1, reused)
      {:ok, item, :loaded} -> collect_ok(rest, [item | items], loaded + 1, reused)
      {:ok, item, :reused} -> collect_ok(rest, [item | items], loaded, reused + 1)
      {:error, error} -> {:error, error}
    end
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
