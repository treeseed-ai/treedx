defmodule TreeDb.Graph.Builder do
  @moduledoc false

  alias TreeDb.Files.PathPolicy
  alias TreeDb.RepositoryQuery.PathMatch

  @extensions ~w(.md .mdx .txt)

  def build_input(ctx, params, previous_manifest) do
    with {:ok, patterns} <- PathMatch.normalize_patterns(params["paths"]),
         {:ok, entries} <- TreeDb.Git.list_tree_recursive(ctx.repo["localPath"], ctx.ref, nil),
         {:ok, documents} <- documents(ctx, entries, patterns, params) do
      {:ok,
       %{
         repoId: ctx.repo["id"],
         refName: ctx.ref,
         commitSha: ctx.resolved_ref,
         documents: documents,
         previousManifest: previous_manifest
       }}
    end
  end

  defp documents(ctx, entries, patterns, params) do
    entries
    |> Enum.filter(&(&1["kind"] == "blob"))
    |> Enum.filter(&(Path.extname(&1["path"]) in @extensions))
    |> Enum.filter(&allowed?(&1["path"], ctx.scope, patterns, params))
    |> Enum.map(&document(ctx, &1))
    |> collect_ok()
  end

  defp document(ctx, entry) do
    with {:ok, blob} <- TreeDb.Git.read_blob(ctx.repo["localPath"], ctx.ref, entry["path"]),
         {:ok, bytes} <- Base.decode64(blob["contentBase64"]),
         true <- String.valid?(bytes) do
      {:ok,
       %{
         path: entry["path"],
         objectId: entry["objectId"],
         size: entry["size"] || blob["byteLength"],
         content: IO.iodata_to_binary(bytes)
       }}
    else
      false -> {:ok, nil}
      :error -> {:ok, nil}
      other -> other
    end
  end

  defp allowed?(path, scope, patterns, params) do
    PathMatch.match_any?(patterns, path) and
      (truthy?(params["allowProtected"]) or !PathPolicy.protected?(path)) and
      match?(:ok, TreeDb.Capabilities.require_paths(scope, [path]))
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

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
