defmodule TreeDx.RepositoryQuery.Sections do
  @moduledoc false

  def extract(document) do
    document["body"]
    |> to_string()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case Regex.run(~r/^(#+)\s+(.+)$/u, line) do
        [_, marks, title] ->
          if String.length(marks) <= 6 do
            [
              %{
                "kind" => "section",
                "path" => document["path"],
                "heading" => String.trim(title),
                "level" => String.length(marks),
                "line" => line_no,
                "snippet" => String.trim(title)
              }
            ]
          else
            []
          end

        _ ->
          []
      end
    end)
  end
end
