defmodule TreeDx.RepositoryQuery.SearchResults do
  @moduledoc false

  alias TreeDx.RepositoryQuery.Filters

  @snippet 160

  def score(documents, params) do
    query = params["query"] || ""
    case_sensitive = truthy?(params["caseSensitive"])

    documents
    |> Enum.map(&score_document(&1, query, case_sensitive))
    |> Enum.reject(&is_nil/1)
  end

  def project(result, params) do
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

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
