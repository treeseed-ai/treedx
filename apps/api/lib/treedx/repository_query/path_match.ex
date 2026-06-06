defmodule TreeDx.RepositoryQuery.PathMatch do
  @moduledoc false

  alias TreeDx.Files.PathPolicy

  def normalize_patterns(nil), do: {:ok, ["**"]}
  def normalize_patterns([]), do: {:ok, ["**"]}

  def normalize_patterns(patterns) when is_list(patterns) do
    patterns
    |> Enum.reduce_while({:ok, []}, fn pattern, {:ok, acc} ->
      case normalize_pattern(pattern) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, patterns} -> {:ok, Enum.reverse(patterns)}
      error -> error
    end
  end

  def normalize_patterns(pattern) when is_binary(pattern), do: normalize_patterns([pattern])

  def normalize_patterns(_),
    do: {:error, %{code: "validation_error", message: "paths must be strings."}}

  def match_any?(patterns, path), do: Enum.any?(patterns, &matches?(&1, path))

  def matches?("**", _path), do: true
  def matches?("*", path), do: !String.contains?(path, "/")

  def matches?(pattern, path) do
    cond do
      String.ends_with?(pattern, "/**") ->
        prefix = String.trim_trailing(pattern, "/**")
        path == prefix or String.starts_with?(path, prefix <> "/")

      String.contains?(pattern, "*") ->
        pattern
        |> Regex.escape()
        |> String.replace("\\*\\*", ".*")
        |> String.replace("\\*", "[^/]*")
        |> then(&Regex.compile!("^#{&1}$"))
        |> Regex.match?(path)

      true ->
        pattern == path
    end
  end

  defp normalize_pattern(pattern) when is_binary(pattern) do
    cond do
      pattern in ["", "**"] ->
        {:ok, "**"}

      String.contains?(pattern, "*") ->
        validate_glob(pattern)

      true ->
        PathPolicy.normalize(pattern, allow_empty: false)
    end
  end

  defp normalize_pattern(_),
    do: {:error, %{code: "validation_error", message: "paths must be strings."}}

  defp validate_glob(pattern) do
    cond do
      String.contains?(pattern, <<0>>) ->
        {:error, %{code: "validation_error", message: "path must not contain NUL bytes."}}

      String.starts_with?(pattern, "/") ->
        {:error, %{code: "validation_error", message: "path must be repository-relative."}}

      String.contains?(pattern, "\\") ->
        {:error, %{code: "validation_error", message: "path must use POSIX separators."}}

      Enum.any?(String.split(pattern, "/", trim: true), &(&1 == "..")) ->
        {:error, %{code: "validation_error", message: "path traversal is not allowed."}}

      true ->
        {:ok, pattern |> String.split("/", trim: true) |> Enum.join("/")}
    end
  end
end
