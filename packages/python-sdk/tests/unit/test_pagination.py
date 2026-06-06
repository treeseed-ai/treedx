from treedx_sdk.pagination import create_page, get_next_cursor, is_treedx_page


def test_page_helpers_preserve_cursor_metadata() -> None:
    page = create_page([1, 2], next_cursor="next", has_more=True)
    assert page.items == [1, 2]
    assert page.next_cursor == "next"
    assert page.has_more is True
    assert get_next_cursor(page) == "next"
    assert is_treedx_page(page)
