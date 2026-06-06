defmodule TreeDxSdk.PaginationTest do
  use ExUnit.Case, async: true

  test "page helpers preserve metadata" do
    page = TreeDxSdk.Pagination.create_page([1, 2], next_cursor: "n", has_more: true)
    assert page.items == [1, 2]
    assert TreeDxSdk.Pagination.get_next_cursor(page) == "n"
    assert page.has_more == true
    assert TreeDxSdk.Pagination.page?(page)
  end
end
