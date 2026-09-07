defmodule TreeDx.Graph.PathSeeds do
  @moduledoc false

  alias TreeDx.RepositoryQuery.ContentPaths

  @max_paths 1000

  # The caller supplies the authorized index, never the unfiltered repository tree.
  def resolve(index, params) do
    available =
      index["nodes"]
      |> Enum.map(& &1["path"])
      |> Enum.filter(&is_binary/1)
      |> Map.new(&{&1, true})

    with {:ok, seeds} <- normalize_seeds(params),
         {:ok, expanded} <- expand(seeds, available) do
      {:ok, Map.put(params, "seeds", expanded)}
    end
  end

  defp normalize_seeds(params) do
    seeds = params["seeds"] || []
    paths = params["paths"] || []
    paths = if is_binary(paths), do: [paths], else: paths

    if is_list(seeds) and is_list(paths) and length(seeds) + length(paths) <= @max_paths do
      {:ok, seeds ++ Enum.map(paths, &%{"value" => &1})}
    else
      invalid("seeds and paths must be lists with at most #{@max_paths} entries.")
    end
  end

  defp expand(seeds, available) do
    seeds
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {seed, position}, {:ok, acc} ->
      case expand_seed(seed, position, available) do
        {:ok, items} when length(acc) + length(items) <= @max_paths ->
          {:cont, {:ok, acc ++ items}}

        {:ok, _items} ->
          {:halt, invalid("Path query matches too many files; narrow the pattern.")}

        error ->
          {:halt, error}
      end
    end)
  end

  defp expand_seed(seed, position, available) when is_map(seed) do
    kind = seed["kind"] || "path"
    id = seed["id"] || "path-#{position}"

    if kind == "path" do
      with value when is_binary(value) and value != "" <- seed["value"],
           {:ok, paths} <- ContentPaths.select([value], available) do
        {:ok,
         Enum.map(paths, fn path ->
           seed |> Map.put("id", id) |> Map.put("kind", "path") |> Map.put("value", path)
         end)}
      else
        {:error, _} = error -> error
        _ -> invalid("Path seeds require a nonempty string value.")
      end
    else
      {:ok, Map.put(seed, "id", id) |> List.wrap()}
    end
  end

  defp expand_seed(_seed, _position, _available), do: invalid("seeds must contain objects.")

  defp invalid(message), do: {:error, %{code: "validation_error", message: message}}
end
