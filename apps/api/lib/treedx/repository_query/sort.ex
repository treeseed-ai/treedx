defmodule TreeDx.RepositoryQuery.Sort do
  @moduledoc false

  alias TreeDx.RepositoryQuery.Filters

  def apply(items, sort) when sort in [nil, []], do: {:ok, items}

  def apply(items, sort) when is_list(sort) do
    if Enum.all?(sort, &valid?/1) do
      {:ok, Enum.sort(items, &before?(&1, &2, sort))}
    else
      {:error, %{code: "validation_error", message: "sort is invalid."}}
    end
  end

  def apply(_items, _sort),
    do: {:error, %{code: "validation_error", message: "sort must be a list."}}

  defp before?(left, right, sort) do
    Enum.reduce_while(sort, false, fn spec, _acc ->
      direction = Map.get(spec, "direction", "desc")
      l = Filters.read_field(left, spec["field"])
      r = Filters.read_field(right, spec["field"])

      case compare(l, r) do
        0 -> {:cont, false}
        cmp -> {:halt, if(direction == "asc", do: cmp < 0, else: cmp > 0)}
      end
    end)
  end

  defp valid?(%{"field" => field} = spec) when is_binary(field) do
    Map.get(spec, "direction", "desc") in ["asc", "desc"]
  end

  defp valid?(_), do: false

  defp compare(left, right) when is_number(left) and is_number(right), do: left - right

  defp compare(left, right),
    do: compare_strings(to_string(left || ""), to_string(right || ""))

  defp compare_strings(left, right) when left < right, do: -1
  defp compare_strings(left, right) when left > right, do: 1
  defp compare_strings(_left, _right), do: 0
end
