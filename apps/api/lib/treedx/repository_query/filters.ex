defmodule TreeDx.RepositoryQuery.Filters do
  @moduledoc false

  @ops ~w(eq in contains prefix gt gte lt lte updated_since related_to)

  def apply(items, filters) when filters in [nil, []], do: {:ok, items}

  def apply(items, filters) when is_list(filters) do
    if Enum.all?(filters, &valid_filter?/1) do
      {:ok, Enum.filter(items, fn item -> Enum.all?(filters, &matches?(item, &1)) end)}
    else
      {:error, %{code: "validation_error", message: "filters are invalid."}}
    end
  end

  def apply(_items, _filters),
    do: {:error, %{code: "validation_error", message: "filters must be a list."}}

  def matches?(item, %{"field" => field, "op" => op} = filter) do
    value = read_field(item, field)
    expected = Map.get(filter, "value")

    case op do
      "eq" -> value == expected
      "in" -> value in List.wrap(expected)
      "contains" -> contains?(value, expected)
      "prefix" -> down(value) |> String.starts_with?(down(expected))
      "gt" -> compare(value, expected) > 0
      "gte" -> compare(value, expected) >= 0
      "lt" -> compare(value, expected) < 0
      "lte" -> compare(value, expected) <= 0
      "updated_since" -> compare(value, expected) >= 0
      "related_to" -> is_list(value) and expected in value
      _ -> false
    end
  end

  def read_field(item, "content"), do: read_field(item, "body")

  def read_field(item, "title") do
    read_path(item, ["frontmatter", "title"]) || read_path(item, ["frontmatter", "name"])
  end

  def read_field(item, "frontmatter." <> rest),
    do: read_path(item, ["frontmatter" | String.split(rest, ".")])

  def read_field(item, field) when field in ["path", "name", "extension", "body", "score"],
    do: item[field]

  def read_field(item, field), do: read_field(item, "frontmatter." <> field)

  defp valid_filter?(%{"field" => field, "op" => op}) when is_binary(field) and op in @ops,
    do: true

  defp valid_filter?(_), do: false

  defp contains?(value, expected) when is_list(value), do: expected in value

  defp contains?(value, expected),
    do: down(value) |> String.contains?(down(expected))

  defp compare(left, right) when is_number(left) and is_number(right), do: left - right

  defp compare(left, right) do
    left_date = parse_time(left)
    right_date = parse_time(right)

    cond do
      left_date && right_date ->
        DateTime.compare(left_date, right_date) |> ordering()

      true ->
        compare_strings(to_string(left || ""), to_string(right || ""))
    end
  end

  defp ordering(:lt), do: -1
  defp ordering(:eq), do: 0
  defp ordering(:gt), do: 1

  defp compare_strings(left, right) when left < right, do: -1
  defp compare_strings(left, right) when left > right, do: 1
  defp compare_strings(_left, _right), do: 0

  defp parse_time(value) do
    case DateTime.from_iso8601(to_string(value || "")) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp read_path(item, path) do
    Enum.reduce_while(path, item, fn segment, current ->
      cond do
        is_map(current) and Map.has_key?(current, segment) -> {:cont, current[segment]}
        true -> {:halt, nil}
      end
    end)
  end

  defp down(value), do: value |> to_string() |> String.downcase()
end
