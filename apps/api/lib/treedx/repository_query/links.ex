defmodule TreeDx.RepositoryQuery.Links do
  @moduledoc false

  def extract(document) do
    markdown_links(document) ++ mdx_imports(document)
  end

  defp markdown_links(document) do
    body = to_string(document["body"])

    Regex.scan(~r/\[([^\]]+)\]\(([^)]+)\)/u, body, return: :index)
    |> Enum.map(fn [{start, _}, {label_start, label_len}, {target_start, target_len}] ->
      %{
        "kind" => "link",
        "path" => document["path"],
        "label" => binary_part(body, label_start, label_len),
        "target" => binary_part(body, target_start, target_len),
        "line" => line_for(body, start)
      }
    end)
  end

  defp mdx_imports(document) do
    document["body"]
    |> to_string()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case Regex.run(~r/^import\s+.+?\s+from\s+['"]([^'"]+)['"]/u, line) do
        [_, target] ->
          [
            %{
              "kind" => "reference",
              "path" => document["path"],
              "target" => target,
              "line" => line_no
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp line_for(body, offset) do
    body
    |> binary_part(0, offset)
    |> String.split("\n")
    |> length()
  end
end
