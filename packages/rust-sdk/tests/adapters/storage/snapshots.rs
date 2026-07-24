mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.snapshots().build("repo/a", json!({})).await.unwrap();
    client.snapshots().get("repo/a", "snap/a").await.unwrap();
    assert!(
        request_keys(&mock).contains(&"GET /api/v1/repos/repo%2Fa/snapshots/snap%2Fa".to_string())
    );
}
