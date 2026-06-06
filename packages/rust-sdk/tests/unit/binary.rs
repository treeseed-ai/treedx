use bytes::Bytes;
use treedx_sdk::binary::{is_binary_body, to_bytes};

#[test]
fn binary_helpers_use_bytes() {
    let body = to_bytes(Bytes::from_static(b"abc"));
    assert!(is_binary_body(&body));
    assert_eq!(body, Bytes::from_static(b"abc"));
}
