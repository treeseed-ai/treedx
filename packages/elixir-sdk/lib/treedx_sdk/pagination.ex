defmodule TreeDxSdk.Pagination do
  @moduledoc false
  defstruct items: [], next_cursor: nil, has_more: nil, cursor: nil, limit: nil

  def create_page(items, opts \\ []) do
    %__MODULE__{
      items: items,
      next_cursor: Keyword.get(opts, :next_cursor) || Keyword.get(opts, :nextCursor),
      has_more: Keyword.get(opts, :has_more) || Keyword.get(opts, :hasMore),
      cursor: Keyword.get(opts, :cursor),
      limit: Keyword.get(opts, :limit)
    }
  end

  def get_next_cursor(%__MODULE__{next_cursor: next_cursor}), do: next_cursor
  def page?(%__MODULE__{}), do: true
  def page?(_), do: false
end
