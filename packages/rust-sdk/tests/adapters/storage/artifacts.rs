mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .artifacts()
        .export("repo/a", json!({}))
        .await
        .unwrap();
    client.artifacts().list("repo/a").await.unwrap();
    client.artifacts().get("repo/a", "art/a").await.unwrap();
    client.artifacts().delete("repo/a", "art/a").await.unwrap();
    assert!(
        request_keys(&mock)
            .contains(&"DELETE /api/v1/repos/repo%2Fa/artifacts/art%2Fa".to_string())
    );
}
