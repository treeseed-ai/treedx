defmodule TreeDx.Search.Ranking do
  @moduledoc false

  def maybe_put_diagnostics(response, _all_results, _page_results, _params, _patterns, false),
    do: response

  def maybe_put_diagnostics(response, all_results, page_results, params, patterns, true) do
    level = params["diagnosticsLevel"] || "summary"

    diagnostics = %{
      level: level,
      authorizedResultCount: length(all_results),
      returnedResultCount: length(page_results),
      searchedPatterns: patterns,
      scoreFactors: score_factors(level, page_results)
    }

    Map.put(response, :diagnostics, diagnostics)
  end

  def include?(params), do: params["includeDiagnostics"] == true

  defp score_factors("ranking", results) do
    Enum.map(results, fn result ->
      %{
        path: result["path"],
        score: result["score"] || 0,
        factors: %{
          lexicalMatches: max((result["score"] || 0) - title_boost(result), 0),
          titleBoost: title_boost(result)
        }
      }
    end)
  end

  defp score_factors(_level, _results), do: ["lexical", "title_boost"]

  defp title_boost(result) do
    if result["score"] && (result["name"] || result["path"]) do
      0
    else
      0
    end
  end
end
