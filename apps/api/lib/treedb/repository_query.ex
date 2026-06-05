defmodule TreeDb.RepositoryQuery do
  @moduledoc false

  alias TreeDb.Files.PathPolicy
  alias TreeDb.RepositoryQuery.{Filters, Links, Pagination, PathMatch, Sections, Sort}
  alias TreeDb.Runtime.Pool
  alias TreeDb.Search.Ranking

  @default_query_limit 20
  @max_query_limit 50
  @default_path_limit 100
  @max_path_limit 500
  @snippet 160

  def read(repo_id, params, principal) do
    Pool.run(:repository_query, fn -> do_read(repo_id, params, principal) end)
  end

  defp do_read(repo_id, params, principal) do
    with {:ok, ctx} <- context(repo_id, params, principal, "files:read"),
         {:ok, paths} <- read_paths(params),
         :ok <- authorize_direct_paths(ctx.scope, paths),
         :ok <- authorize_protected_direct(paths, truthy?(params["allowProtected"])),
         {:ok, files} <- read_files(ctx, paths, params) do
      audit("repo.files_read", ctx, %{paths: paths, resultCount: length(files)})

      response = base_response(ctx)

      {:ok,
       if(Map.has_key?(params, "paths"),
         do: Map.put(response, :files, files),
         else: Map.put(response, :file, List.first(files))
       )}
    end
  end

  def paths(repo_id, params, principal) do
    Pool.run(:repository_query, fn -> do_paths(repo_id, params, principal) end)
  end

  defp do_paths(repo_id, params, principal) do
    with {:ok, ctx} <- context(repo_id, params, principal, "files:read"),
         {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, entries} <- filtered_entries(ctx, patterns, params),
         {:ok, entries} <- filter_kinds(entries, params["kinds"]),
         entries <- filter_extensions(entries, params["extensions"]),
         {page_entries, page} <-
           Pagination.paginate(
             entries,
             params["limit"],
             params["cursor"],
             @default_path_limit,
             @max_path_limit
           ) do
      audit("repo.paths_listed", ctx, %{
        paths: patterns,
        resultCount: length(page_entries)
      })

      {:ok,
       base_response(ctx)
       |> Map.merge(%{entries: Enum.map(page_entries, &path_entry/1), page: page})}
    end
  end

  def search(repo_id, params, principal) do
    Pool.run(:repository_query, fn -> do_search(repo_id, params, principal) end)
  end

  defp do_search(repo_id, params, principal) do
    with {:ok, ctx} <- context(repo_id, params, principal, "files:search"),
         :ok <- validate_query(params["query"], false),
         {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, documents} <- searchable_documents(ctx, patterns, params),
         {:ok, filtered} <- Filters.apply(documents, params["filters"] || []),
         results <- text_results(filtered, params),
         {:ok, sorted} <-
           Sort.apply(results, params["sort"] || [%{"field" => "score", "direction" => "desc"}]),
         {page_results, page} <-
           Pagination.paginate(
             sorted,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      audit("repo.files_searched", ctx, %{paths: patterns, resultCount: length(page_results)})

      response =
        base_response(ctx)
        |> Map.merge(%{
          query: params["query"],
          results: Enum.map(page_results, &project_search_result(&1, params)),
          page: page
        })
        |> Ranking.maybe_put_diagnostics(
          results,
          page_results,
          params,
          patterns,
          Ranking.include?(params)
        )

      {:ok, response}
    end
  end

  def query(repo_id, params, principal) do
    Pool.run(:repository_query, fn -> do_query(repo_id, params, principal) end)
  end

  defp do_query(repo_id, params, principal) do
    type = params["type"] || "text"
    capability = query_capability(type)

    with {:ok, ctx} <- context(repo_id, params, principal, capability),
         {:ok, result} <- execute_query(type, ctx, params) do
      audit("repo.query_executed", ctx, %{
        paths: params["paths"] || ["**"],
        queryType: type,
        resultCount: length(Map.get(result, :results, []))
      })

      {:ok, result}
    end
  end

  defp execute_query("path", ctx, params), do: path_query(ctx, params)
  defp execute_query("text", ctx, params), do: search_query(ctx, params)
  defp execute_query("frontmatter", ctx, params), do: frontmatter_query(ctx, params)
  defp execute_query("section", ctx, params), do: section_query(ctx, params)
  defp execute_query("link", ctx, params), do: link_query(ctx, params)
  defp execute_query("changed_path", ctx, params), do: changed_path_query(ctx, params)
  defp execute_query("combined", ctx, params), do: combined_query(ctx, params)

  defp execute_query(_type, _ctx, _params),
    do: {:error, %{code: "validation_error", message: "query type is not supported."}}

  defp path_query(ctx, params) do
    with {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, entries} <- filtered_entries(ctx, patterns, params),
         entries <- filter_extensions(entries, params["extensions"]),
         entries <- filter_path_query(entries, params["query"]),
         {page_entries, page} <-
           Pagination.paginate(
             entries,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      {:ok,
       base_response(ctx)
       |> Map.merge(%{
         type: "path",
         results: Enum.map(page_entries, &Map.put(path_entry(&1), :kind, "path")),
         page: page
       })}
    end
  end

  defp search_query(ctx, params) do
    with {:ok, response} <-
           do_search(ctx.repo["id"], Map.put(params, "__ctx", ctx), ctx.principal) do
      {:ok, response |> Map.put(:type, "text")}
    end
  end

  defp frontmatter_query(ctx, params) do
    with {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, documents} <- searchable_documents(ctx, patterns, params),
         {:ok, filtered} <- Filters.apply(documents, params["filters"] || []),
         {:ok, sorted} <- Sort.apply(filtered, params["sort"] || []),
         {page_docs, page} <-
           Pagination.paginate(
             sorted,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      {:ok,
       base_response(ctx)
       |> Map.merge(%{
         type: "frontmatter",
         results:
           Enum.map(
             page_docs,
             &Map.take(&1, ["path", "name", "extension", "objectId", "frontmatter"])
           ),
         page: page
       })}
    end
  end

  defp section_query(ctx, params) do
    with {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, documents} <- searchable_documents(ctx, patterns, params),
         sections <- Enum.flat_map(documents, &Sections.extract/1),
         sections <- filter_textish(sections, params["query"], "heading"),
         {page_sections, page} <-
           Pagination.paginate(
             sections,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      {:ok,
       base_response(ctx) |> Map.merge(%{type: "section", results: page_sections, page: page})}
    end
  end

  defp link_query(ctx, params) do
    with {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, documents} <- searchable_documents(ctx, patterns, params),
         links <- Enum.flat_map(documents, &Links.extract/1),
         links <- filter_textish(links, params["query"], "target"),
         {page_links, page} <-
           Pagination.paginate(
             links,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      {:ok, base_response(ctx) |> Map.merge(%{type: "link", results: page_links, page: page})}
    end
  end

  defp changed_path_query(ctx, params) do
    base_ref = params["baseRef"]

    with true <- is_binary(base_ref) and base_ref != "",
         {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(ctx.principal, "files:read", ctx.repo["id"]),
         :ok <- TreeDb.Capabilities.require_ref(ctx.scope, base_ref),
         {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, changes} <-
           TreeDb.Git.changed_paths(TreeDb.RepositoryStorage.path!(ctx.repo), base_ref, ctx.ref),
         changes <- filter_changed_paths(changes, ctx.scope, patterns, params),
         {page_changes, page} <-
           Pagination.paginate(
             changes,
             params["limit"],
             params["cursor"],
             @default_query_limit,
             @max_query_limit
           ) do
      {:ok,
       base_response(ctx)
       |> Map.merge(%{type: "changed_path", baseRef: base_ref, results: page_changes, page: page})}
    else
      false -> {:error, %{code: "validation_error", message: "baseRef is required."}}
      other -> other
    end
  end

  defp combined_query(ctx, params) do
    with {:ok, text} <- search_query(ctx, params),
         {:ok, sections} <- section_query(ctx, params) do
      results =
        Enum.map(text.results, &Map.put(&1, :kind, "text")) ++
          Enum.map(sections.results, &Map.put(&1, "kind", "section"))

      {page_results, page} =
        Pagination.paginate(
          results,
          params["limit"],
          params["cursor"],
          @default_query_limit,
          @max_query_limit
        )

      {:ok,
       base_response(ctx) |> Map.merge(%{type: "combined", results: page_results, page: page})}
    end
  end

  def context(_repo_id, %{"__ctx" => ctx}, _principal, _capability), do: {:ok, ctx}

  def context(repo_id, params, principal, capability) do
    with {:ok, scope} <- TreeDb.Capabilities.require_capability(principal, capability, repo_id),
         {:ok, repo} when is_map(repo) <- repository_for_context(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         :ok <- TreeDb.Capabilities.require_ref(scope, ref),
         {:ok, resolved} <- TreeDb.Git.resolve_ref(TreeDb.RepositoryStorage.path!(repo), ref) do
      {:ok,
       %{
         repo: repo,
         ref: ref,
         resolved_ref: resolved["target"],
         scope: scope,
         principal: principal
       }}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  defp repository_for_context(repo_id) do
    case TreeDb.Store.get_repository(repo_id) do
      {:ok, repo} when is_map(repo) ->
        {:ok, repo}

      _ ->
        mirror_repository_for_context(repo_id)
    end
  end

  defp mirror_repository_for_context(repo_id) do
    local_node = TreeDb.Federation.NodeIdentity.node_id()

    with {:ok, route} when is_map(route) <- TreeDb.Store.get_federation_route(repo_id),
         true <- local_node in (route["mirrorNodeIds"] || []),
         repository_name when is_binary(repository_name) and repository_name != "" <-
           route["repositoryName"] do
      {:ok,
       %{
         "id" => repo_id,
         "repositoryName" => repository_name,
         "defaultRef" => route["defaultRef"] || "refs/heads/main",
         "storageKind" => "mirror",
         "storageRelativePath" => TreeDb.RepositoryStorage.mirror_relative_path(repository_name)
       }}
    else
      _ -> {:ok, nil}
    end
  end

  defp query_capability("text"), do: "files:search"
  defp query_capability("combined"), do: "files:search"
  defp query_capability("changed_path"), do: "git:diff"
  defp query_capability(_), do: "files:read"

  defp read_paths(%{"paths" => paths}) when is_list(paths) do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case PathPolicy.normalize(path) do
        {:ok, path} -> {:cont, {:ok, [path | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      other -> other
    end
  end

  defp read_paths(%{"path" => path}),
    do:
      PathPolicy.normalize(path)
      |> then(fn
        {:ok, path} -> {:ok, [path]}
        other -> other
      end)

  defp read_paths(_),
    do: {:error, %{code: "validation_error", message: "path or paths is required."}}

  defp authorize_direct_paths(scope, paths), do: TreeDb.Capabilities.require_paths(scope, paths)

  defp authorize_protected_direct(paths, allow_protected) do
    if !allow_protected and Enum.any?(paths, &PathPolicy.protected?/1) do
      {:error,
       %{code: "permission_denied", message: "Permission denied.", details: %{protected: true}}}
    else
      :ok
    end
  end

  defp read_files(ctx, paths, params) do
    paths
    |> Enum.map(fn path ->
      TreeDb.RepositoryCache.document(ctx, path,
        encoding: params["encoding"] || "utf8",
        parse_frontmatter: params["parseFrontmatter"] != false
      )
    end)
    |> collect_ok()
  end

  defp filtered_entries(ctx, patterns, params) do
    with {:ok, entries} <- TreeDb.RepositoryCache.tree_entries(ctx) do
      allow_protected = truthy?(params["allowProtected"])

      entries =
        entries
        |> Enum.filter(&entry_allowed?(&1, ctx.scope, patterns, allow_protected))
        |> Enum.sort_by(& &1["path"])

      {:ok, entries}
    end
  end

  defp entry_allowed?(entry, scope, patterns, allow_protected) do
    path = entry["path"]

    PathMatch.match_any?(patterns, path) and
      (allow_protected or !PathPolicy.protected?(path)) and
      match?(
        :ok,
        TreeDb.Capabilities.require_paths(scope, [path])
      )
  end

  defp searchable_documents(ctx, patterns, params) do
    with {:ok, documents} <- TreeDb.RepositoryCache.searchable_documents(ctx) do
      allow_protected = truthy?(params["allowProtected"])

      {:ok,
       Enum.filter(documents, fn doc ->
         entry_allowed?(%{"path" => doc["path"]}, ctx.scope, patterns, allow_protected)
       end)}
    end
  end

  defp text_results(documents, params) do
    query = params["query"] || ""
    case_sensitive = truthy?(params["caseSensitive"])

    documents
    |> Enum.map(&score_document(&1, query, case_sensitive))
    |> Enum.reject(&is_nil/1)
  end

  defp score_document(document, "", _case_sensitive), do: Map.put(document, "score", 0)

  defp score_document(document, query, case_sensitive) do
    body = document["body"] || document["content"] || ""
    haystack = if case_sensitive, do: body, else: String.downcase(body)
    needle = if case_sensitive, do: query, else: String.downcase(query)

    case :binary.match(haystack, needle) do
      {offset, _len} ->
        {line, column, snippet} = locate(body, offset)
        score = count_matches(haystack, needle) + title_boost(document, needle, case_sensitive)

        document
        |> Map.put("score", score)
        |> Map.put("line", line)
        |> Map.put("column", column)
        |> Map.put("snippet", snippet)

      :nomatch ->
        nil
    end
  end

  defp count_matches(_haystack, ""), do: 0

  defp count_matches(haystack, needle) do
    haystack
    |> String.split(needle)
    |> length()
    |> Kernel.-(1)
  end

  defp title_boost(document, needle, case_sensitive) do
    title = Filters.read_field(document, "title") || document["path"]

    comparable =
      if case_sensitive, do: to_string(title), else: title |> to_string() |> String.downcase()

    if String.contains?(comparable, needle), do: 2, else: 0
  end

  defp locate(body, offset) do
    before = binary_part(body, 0, offset)
    line = before |> String.split("\n") |> length()
    column = offset - (before |> String.split("\n") |> List.last() |> byte_size()) + 1
    line_text = body |> String.split("\n") |> Enum.at(line - 1, "")
    start = max(column - div(@snippet, 2), 0)
    {line, column, line_text |> String.slice(start, @snippet) |> String.trim()}
  end

  defp project_search_result(result, params) do
    %{
      path: result["path"],
      name: result["name"],
      extension: result["extension"],
      objectId: result["objectId"],
      score: result["score"],
      line: result["line"],
      column: result["column"],
      snippet: result["snippet"],
      frontmatter:
        if(params["includeFrontmatter"] == false, do: nil, else: result["frontmatter"]),
      body: if(truthy?(params["includeBody"]), do: result["body"], else: nil)
    }
  end

  defp filter_kinds(entries, nil), do: {:ok, entries}
  defp filter_kinds(entries, []), do: {:ok, entries}

  defp filter_kinds(entries, kinds) when is_list(kinds) do
    if Enum.all?(kinds, &(&1 in ["blob", "tree"])) do
      {:ok, Enum.filter(entries, &(&1["kind"] in kinds))}
    else
      {:error, %{code: "validation_error", message: "kinds are invalid."}}
    end
  end

  defp filter_kinds(_entries, _),
    do: {:error, %{code: "validation_error", message: "kinds must be a list."}}

  defp filter_extensions(entries, nil), do: entries
  defp filter_extensions(entries, []), do: entries

  defp filter_extensions(entries, extensions) when is_list(extensions) do
    Enum.filter(entries, &(Path.extname(&1["path"]) in extensions))
  end

  defp filter_extensions(entries, _), do: entries

  defp filter_path_query(entries, nil), do: entries
  defp filter_path_query(entries, ""), do: entries

  defp filter_path_query(entries, query) do
    needle = String.downcase(to_string(query))
    Enum.filter(entries, &(String.downcase(&1["path"]) |> String.contains?(needle)))
  end

  defp filter_textish(items, nil, _field), do: items
  defp filter_textish(items, "", _field), do: items

  defp filter_textish(items, query, field) do
    needle = String.downcase(query)
    Enum.filter(items, &(String.downcase(to_string(&1[field] || "")) |> String.contains?(needle)))
  end

  defp filter_changed_paths(changes, scope, patterns, params) do
    allow_protected = truthy?(params["allowProtected"])

    changes
    |> Enum.filter(&entry_allowed?(&1, scope, patterns, allow_protected))
    |> Enum.map(fn change ->
      %{
        kind: "changed_path",
        path: change["path"],
        status: change["status"],
        baseObjectId: change["baseObjectId"],
        objectId: change["objectId"]
      }
    end)
  end

  defp path_entry(entry) do
    %{
      path: entry["path"],
      name: Path.basename(entry["path"]),
      kind: entry["kind"],
      extension: Path.extname(entry["path"]),
      objectId: entry["objectId"],
      mode: entry["mode"],
      size: entry["size"]
    }
  end

  defp validate_query(nil, true), do: :ok
  defp validate_query("", true), do: :ok

  defp validate_query(query, _optional) when is_binary(query) do
    if String.length(query) <= 200,
      do: :ok,
      else: {:error, %{code: "validation_error", message: "query is too long."}}
  end

  defp validate_query(_query, _optional),
    do: {:error, %{code: "validation_error", message: "query is required."}}

  defp base_response(ctx),
    do: %{repoId: ctx.repo["id"], ref: ctx.ref, resolvedRef: ctx.resolved_ref}

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

  defp audit(event_type, ctx, data) do
    TreeDb.Audit.append(event_type, %{
      actor_id: ctx.principal["actorId"],
      tenant_id: ctx.principal["tenantId"],
      repo_id: ctx.repo["id"],
      data: Map.merge(%{ref: ctx.ref, resolvedRef: ctx.resolved_ref}, data)
    })
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
