defmodule TreeDb.RepositoryCache do
  @moduledoc false
  use GenServer

  alias TreeDb.Cache
  alias TreeDb.RepositoryQuery.Document

  @table __MODULE__
  @extensions ~w(.md .mdx .markdown .txt .json)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    Cache.ensure_table(@table)
    {:ok, %{}}
  end

  def reset!, do: Cache.reset(@table)

  def tree_entries(ctx) do
    get_or_load(ctx, :tree, fn ->
      TreeDb.Git.list_tree_recursive(ctx.repo["localPath"], ctx.ref, nil)
    end)
  end

  def searchable_documents(ctx) do
    get_or_load(ctx, :documents, fn ->
      with {:ok, entries} <- tree_entries(ctx) do
        entries
        |> Enum.filter(&(&1["kind"] == "blob"))
        |> Enum.filter(&(Path.extname(&1["path"]) in @extensions))
        |> Enum.map(fn entry ->
          case Document.from_entry(ctx.repo, ctx.ref, entry,
                 encoding: "utf8",
                 parse_frontmatter: true
               ) do
            {:ok, doc} -> {:ok, doc}
            {:error, %{code: "unsupported_media_type"}} -> {:ok, nil}
            other -> other
          end
        end)
        |> collect_ok()
        |> case do
          {:ok, docs} -> {:ok, Enum.reject(docs, &is_nil/1)}
          other -> other
        end
      end
    end)
  end

  def document(ctx, path, opts) do
    encoding = Keyword.get(opts, :encoding, "utf8")
    parse_frontmatter = Keyword.get(opts, :parse_frontmatter, true)

    if encoding == "utf8" and parse_frontmatter do
      with {:ok, docs} <- searchable_documents(ctx),
           doc when is_map(doc) <- Enum.find(docs, &(&1["path"] == path)) do
        {:ok, doc}
      else
        nil -> Document.from_path(ctx.repo, ctx.ref, path, opts)
        other -> other
      end
    else
      Document.from_path(ctx.repo, ctx.ref, path, opts)
    end
  end

  defp get_or_load(ctx, kind, loader) do
    if Cache.enabled?("TREEDB_REPO_DOC_CACHE_ENABLED", true) and Process.whereis(__MODULE__) do
      Cache.get_or_load(
        @table,
        key(ctx, kind),
        Cache.int_env("TREEDB_REPO_DOC_CACHE_TTL_MS", 300_000),
        Cache.int_env("TREEDB_REPO_DOC_CACHE_MAX_ENTRIES", 256),
        loader
      )
    else
      loader.()
    end
  end

  defp key(ctx, kind),
    do: {kind, ctx.repo["id"], ctx.repo["localPath"], ctx.ref, ctx.resolved_ref}

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
end
