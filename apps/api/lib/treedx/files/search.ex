defmodule TreeDx.Files.Search do
  @moduledoc false

  @snippet 160

  def find(files, query, limit, case_sensitive) do
    needle = if case_sensitive, do: query, else: String.downcase(query)

    files
    |> Enum.flat_map(fn {path, content, source} ->
      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_no} ->
        haystack = if case_sensitive, do: line, else: String.downcase(line)

        case :binary.match(haystack, needle) do
          {column, _len} ->
            [
              %{
                path: path,
                line: line_no,
                column: column + 1,
                snippet: snippet(line, column),
                source: source
              }
            ]

          :nomatch ->
            []
        end
      end)
    end)
    |> Enum.take(limit + 1)
  end

  defp snippet(line, column) do
    start = max(column - div(@snippet, 2), 0)
    line |> String.slice(start, @snippet) |> String.trim()
  end
end
