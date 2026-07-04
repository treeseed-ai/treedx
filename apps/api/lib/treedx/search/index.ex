defmodule TreeDx.Search.Index do
  @moduledoc false

  alias TreeDx.Files.PathPolicy
  alias TreeDx.RepositoryQuery.{Document, PathMatch}

  @extensions ~w(.md .mdx .txt .json)

  def refresh(repo_id, params, principal) do
    with {:ok, ctx} <- TreeDx.RepositoryQuery.context(repo_id, params, principal, "files:search"),
         {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, documents} <- documents(ctx, patterns, params),
         {:ok, manifest} <- latest_graph_manifest(repo_id, ctx.ref),
         {:ok, segment} <- write_segment(ctx, documents),
         {:ok, record} <- write_manifest(ctx, documents, segment, manifest) do
      audit("search.index_refreshed", ctx, %{
        indexVersion: record["indexVersion"],
        pathCount: length(record["indexedPaths"] || [])
      })

      {:ok,
       %{
         index: %{
           repoId: repo_id,
           ref: ctx.ref,
           resolvedRef: ctx.resolved_ref,
           indexVersion: record["indexVersion"],
           graphVersion: record["graphVersion"],
           segmentIds: record["segmentIds"] || [],
           indexedPathCount: length(record["indexedPaths"] || []),
           sourceCommit: record["sourceCommit"],
           stale: record["stale"] || false
         }
       }}
    end
  end

  def status(repo_id, params, principal) do
    with {:ok, ctx} <- TreeDx.RepositoryQuery.context(repo_id, params, principal, "files:search"),
         {:ok, manifest} <- TreeDx.Store.get_search_index_manifest(repo_id, ctx.ref),
         {:ok, segments} <- TreeDx.Store.list_search_index_segments(repo_id, ctx.ref) do
      {:ok,
       %{
         index: %{
           repoId: repo_id,
           ref: ctx.ref,
           resolvedRef: ctx.resolved_ref,
           ready: is_map(manifest),
           indexVersion: manifest && manifest["indexVersion"],
           graphVersion: manifest && manifest["graphVersion"],
           segmentIds: (manifest && manifest["segmentIds"]) || [],
           indexedPathCount: (manifest && length(manifest["indexedPaths"] || [])) || 0,
           segmentCount: length(segments),
           sourceCommit: manifest && manifest["sourceCommit"],
           stale: stale?(manifest, ctx.resolved_ref)
         }
       }}
    end
  end

  def compact(repo_id, params, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_capability(principal, "policy:write", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         {:ok, result} <-
           TreeDx.Store.compact_search_index(%{
             repoId: repo_id,
             refName: ref,
             plan: params["planOnly"] == true
           }) do
      {:ok,
       %{
         compact: %{
           repoId: repo_id,
           ref: ref,
           planOnly: result["plan"],
           segmentsBefore: result["segmentsBefore"],
           segmentsAfter: result["segmentsAfter"],
           compacted: result["compacted"]
         }
       }}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  defp documents(ctx, patterns, params) do
    with {:ok, entries} <-
           TreeDx.Git.list_tree_recursive(TreeDx.RepositoryStorage.path!(ctx.repo), ctx.ref, nil) do
      entries
      |> Enum.filter(&(&1["kind"] == "blob"))
      |> Enum.filter(&(Path.extname(&1["path"]) in @extensions))
      |> Enum.filter(&allowed?(&1["path"], ctx.scope, patterns, params))
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
  end

  defp write_segment(ctx, documents) do
    paths = Enum.map(documents, & &1["path"])
    content_hash = hash_payload(%{paths: paths, objects: Enum.map(documents, & &1["objectId"])})

    segment_id =
      "sseg_" <> String.slice(String.replace_prefix(content_hash, "blake3:", ""), 0, 24)

    TreeDx.Store.put_search_index_segment(%{
      segmentId: segment_id,
      repoId: ctx.repo["id"],
      refName: ctx.ref,
      pathCount: length(paths),
      documentCount: length(documents),
      contentHash: content_hash,
      createdAt: now()
    })
  end

  defp write_manifest(ctx, documents, segment, graph_manifest) do
    paths = documents |> Enum.map(& &1["path"]) |> Enum.sort()

    index_hash =
      hash_payload(%{repo: ctx.repo["id"], ref: ctx.ref, commit: ctx.resolved_ref, paths: paths})

    TreeDx.Store.put_search_index_manifest(%{
      indexVersion:
        "sidx_" <> String.slice(String.replace_prefix(index_hash, "blake3:", ""), 0, 24),
      repoId: ctx.repo["id"],
      refName: ctx.ref,
      graphVersion: graph_manifest && graph_manifest["graphVersion"],
      segmentIds: [segment["segmentId"]],
      indexedPaths: paths,
      sourceCommit: ctx.resolved_ref,
      stale: false,
      createdAt: now()
    })
  end

  defp latest_graph_manifest(repo_id, ref) do
    case TreeDx.Graph.Native.read_latest_graph_manifest(repo_id, ref) do
      {:ok, nil} -> {:ok, nil}
      other -> other
    end
  end

  defp stale?(nil, _resolved_ref), do: false
  defp stale?(manifest, resolved_ref), do: manifest["sourceCommit"] not in [nil, resolved_ref]

  defp allowed?(path, scope, patterns, params) do
    PathMatch.match_any?(patterns, path) and
      (params["allowProtected"] == true or !PathPolicy.protected?(path)) and
      match?(:ok, TreeDx.Capabilities.require_paths(scope, [path]))
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, nil}, {:ok, acc} -> {:cont, {:ok, acc}}
      {:ok, item}, {:ok, acc} -> {:cont, {:ok, [item | acc]}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      other -> other
    end
  end

  defp hash_payload(payload) do
    {:ok, hash} = TreeDx.Store.hash_bytes_base64(payload |> Jason.encode!() |> Base.encode64())
    hash
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp audit(event_type, ctx, data) do
    TreeDx.Audit.append(event_type, %{
      actor_id: ctx.principal["actorId"],
      tenant_id: ctx.principal["tenantId"],
      repo_id: ctx.repo["id"],
      data: Map.merge(%{ref: ctx.ref, resolvedRef: ctx.resolved_ref}, data)
    })
  end
end
