defmodule TreeDx.RepositoryQuery.ContentPaths do
  @moduledoc false

  @content_extensions [".mdx", ".md", ".markdown", ".json", ".yaml", ".yml", ".toml"]

  def resolve(ctx, paths) do
    if Enum.any?(paths, &(Path.extname(&1) == "")) do
      with {:ok, entries} <- TreeDx.RepositoryCache.tree_entries(ctx) do
        available =
          entries
          |> Enum.filter(&(&1["kind"] == "blob"))
          |> Map.new(&{&1["path"], true})

        paths
        |> Enum.map(&resolve_path(&1, available))
        |> collect_ok()
      end
    else
      {:ok, Enum.map(paths, &resolution(&1, &1))}
    end
  end

  def read(ctx, paths, params) do
    with {:ok, bounds} <- TreeDx.RepositoryQuery.BoundedRead.normalize(paths, params) do
      paths
      |> Enum.map(&read_one(ctx, &1, params, bounds))
      |> collect_ok()
    end
  end

  defp read_one(ctx, path, params, bounds) do
    with {:ok, document} <-
           TreeDx.RepositoryCache.document(ctx, path.source,
             encoding: params["encoding"] || "utf8",
             parse_frontmatter: params["parseFrontmatter"] != false
           ) do
      document
      |> Map.put("logicalPath", path.logical)
      |> Map.put("sourcePath", path.source)
      |> Map.put("requestedPath", path.requested)
      |> TreeDx.RepositoryQuery.BoundedRead.project(bounds)
    end
  end

  defp resolve_path(path, available) do
    if Map.has_key?(available, path) do
      {:ok, resolution(path, path)}
    else
      resolve_extension(path, available)
    end
  end

  defp resolve_extension(path, available) do
    matches =
      @content_extensions
      |> Enum.map(&(path <> &1))
      |> Enum.filter(&Map.has_key?(available, &1))

    case matches do
      [source] ->
        {:ok, resolution(path, source)}

      [] ->
        {:ok, resolution(path, path)}

      sources ->
        {:error,
         %{
           code: "conflict",
           message: "Content identifier resolves to multiple repository files.",
           details: %{logicalPath: path, matchCount: length(sources)}
         }}
    end
  end

  defp resolution(requested, source) do
    %{requested: requested, logical: logical_path(source), source: source}
  end

  defp logical_path(path) do
    extension = Path.extname(path)
    if extension in @content_extensions, do: String.trim_trailing(path, extension), else: path
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      other -> other
    end
  end
end
