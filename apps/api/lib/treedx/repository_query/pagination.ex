defmodule TreeDx.RepositoryQuery.Pagination do
  @moduledoc false

  def paginate(items, limit, cursor, default_limit, max_limit) do
    limit = limit |> coerce_int(default_limit) |> max(1) |> min(max_limit)
    offset = decode_cursor(cursor)

    page_items = items |> Enum.drop(offset) |> Enum.take(limit + 1)
    has_more = length(page_items) > limit
    returned = Enum.take(page_items, limit)

    next_cursor =
      if has_more do
        encode_cursor(offset + limit)
      else
        nil
      end

    {returned, %{limit: limit, nextCursor: next_cursor, hasMore: has_more}}
  end

  defp decode_cursor(nil), do: 0
  defp decode_cursor(""), do: 0

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"offset" => offset}} when is_integer(offset) and offset >= 0 <-
           Jason.decode(json) do
      offset
    else
      _ -> 0
    end
  end

  defp decode_cursor(_), do: 0

  defp encode_cursor(offset) do
    %{offset: offset}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp coerce_int(value, _default) when is_integer(value), do: value

  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> default
    end
  end

  defp coerce_int(_value, default), do: default
end
