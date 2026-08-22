defmodule TreeDx.RepositoryCache do
  @moduledoc false
  use GenServer

  alias TreeDx.Cache
  alias TreeDx.RepositoryQuery.Document
  alias TreeDx.Runtime.Pool

  @table __MODULE__
  @extensions ~w(.md .mdx .markdown .txt .json)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    Cache.ensure_table(@table)
    {:ok, %{}}
  end

  def reset!, do: Cache.reset(@table)

  def invalidate_repository(repo_id) when is_binary(repo_id) do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.each(fn entry ->
        key = elem(entry, 0)
        if repository_key?(key, repo_id), do: Cache.delete(@table, key)
      end)
    end

    :ok
  end

  def warm(repo) when is_map(repo) do
    requested_ref = repo["defaultRef"] || "refs/heads/main"

    with {:ok, context} <-
           context(repo["id"], requested_ref, fn ->
             with {:ok, resolved} <-
                    TreeDx.Git.resolve_ref(TreeDx.RepositoryStorage.path!(repo), requested_ref) do
               {:ok, %{repo: repo, ref: requested_ref, resolved_ref: resolved["target"]}}
             end
           end),
         {:ok, _default_context} <-
           context(repo["id"], nil, fn -> {:ok, context} end),
         {:ok, _documents} <- searchable_documents(context) do
      :ok
    end
  end

  def context(repo_id, requested_ref, loader) do
    max_bytes = cache_max_bytes()

    Cache.get_or_load(
      @table,
      {:repository_context, repo_id, requested_ref || :default},
      Cache.int_env("TREEDX_REPO_CONTEXT_CACHE_TTL_MS", 300_000),
      Cache.entry_limit("TREEDX_REPO_CONTEXT_CACHE_MAX_ENTRIES", 1024, max_bytes),
      max_bytes,
      fn -> bounded_load(loader) end
    )
  end

  def authorization_scope(actor_id, repo_id, loader) do
    max_bytes = cache_max_bytes()

    Cache.get_or_load(
      @table,
      {:authorization_scope, actor_id, repo_id || :global},
      Cache.int_env("TREEDX_AUTHORIZATION_CACHE_TTL_MS", 300_000),
      Cache.entry_limit("TREEDX_AUTHORIZATION_CACHE_MAX_ENTRIES", 4096, max_bytes),
      max_bytes,
      fn -> bounded_load(loader) end
    )
  end

  def tree_entries(ctx) do
    get_or_load(ctx, :tree, fn ->
      bounded_load(fn ->
        TreeDx.Git.list_tree_recursive(TreeDx.RepositoryStorage.path!(ctx.repo), ctx.ref, nil)
      end)
    end)
  end

  def searchable_documents(ctx) do
    get_or_load(ctx, :documents, fn ->
      bounded_load(fn ->
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
    end)
  end

  def document(ctx, path, opts) do
    encoding = Keyword.get(opts, :encoding, "utf8")
    parse_frontmatter = Keyword.get(opts, :parse_frontmatter, true)

    get_or_load(ctx, {:document, path, encoding, parse_frontmatter}, fn ->
      bounded_load(fn -> Document.from_path(ctx.repo, ctx.ref, path, opts) end)
    end)
  end

  def result(ctx, operation, params, loader) do
    identity = {
      ctx.principal["actorId"],
      ctx.principal["tenantId"],
      ctx.scope["policyHash"],
      ctx.scope["policyVersion"],
      effective_scope_identity(ctx.scope)
    }

    get_or_load(
      ctx,
      {:result, operation, identity, params},
      Cache.int_env("TREEDX_QUERY_RESULT_CACHE_TTL_MS", 300_000),
      loader
    )
  end

  defp effective_scope_identity(scope) do
    {
      scope["repoIds"] || [],
      scope["capabilities"] || [],
      scope["refs"] || [],
      scope["paths"] || []
    }
  end

  defp bounded_load(loader), do: Pool.run(:repository_query, loader)

  defp get_or_load(ctx, kind, loader) do
    get_or_load(ctx, kind, Cache.int_env("TREEDX_REPO_DOC_CACHE_TTL_MS", 300_000), loader)
  end

  defp get_or_load(ctx, kind, ttl_ms, loader) do
    if Cache.enabled?("TREEDX_REPO_DOC_CACHE_ENABLED", true) and Process.whereis(__MODULE__) do
      max_bytes = cache_max_bytes()

      Cache.get_or_load(
        @table,
        key(ctx, kind),
        ttl_ms,
        Cache.entry_limit("TREEDX_REPO_DOC_CACHE_MAX_ENTRIES", 256, max_bytes),
        max_bytes,
        loader
      )
    else
      loader.()
    end
  end

  defp key(ctx, kind),
    do:
      {kind, ctx.repo["id"], TreeDx.RepositoryStorage.path!(ctx.repo), ctx.ref, ctx.resolved_ref}

  defp repository_key?({:repository_context, repo_id, _requested_ref}, repo_id), do: true
  defp repository_key?({:authorization_scope, _actor_id, repo_id}, repo_id), do: true
  defp repository_key?({_kind, repo_id, _path, _ref, _resolved_ref}, repo_id), do: true
  defp repository_key?(_key, _repo_id), do: false

  defp cache_max_bytes do
    case System.get_env("TREEDX_REPO_DOC_CACHE_MAX_BYTES") do
      nil -> TreeDx.Runtime.Resources.cache_budget_for(:repo_doc)
      "" -> TreeDx.Runtime.Resources.cache_budget_for(:repo_doc)
      value -> parse_positive_int(value) || TreeDx.Runtime.Resources.cache_budget_for(:repo_doc)
    end
  end

  defp parse_positive_int(value) do
    case Integer.parse(value) do
      {int, _} when int > 0 -> int
      _ -> nil
    end
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
end
