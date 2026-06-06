use treedx_sdk::TreeDxPage;
use treedx_sdk::pagination::{create_page, get_next_cursor};

#[test]
fn page_helpers_preserve_cursor_metadata() {
    let mut page = create_page(vec![1, 2]);
    page.next_cursor = Some("cursor-2".to_string());
    page.has_more = Some(true);
    assert_eq!(page.items, vec![1, 2]);
    assert_eq!(get_next_cursor(&page), Some("cursor-2"));
    assert_eq!(page.has_more, Some(true));

    let explicit = TreeDxPage {
        items: vec![3],
        next_cursor: None,
        has_more: Some(false),
        cursor: None,
        limit: Some(1),
    };
    assert_eq!(explicit.limit, Some(1));
}
