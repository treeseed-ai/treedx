mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .migrations()
        .create("repo/a", json!({}))
        .await
        .unwrap();
    client.migrations().get("repo/a", "mig/a").await.unwrap();
    assert!(
        request_keys(&mock).contains(&"GET /api/v1/repos/repo%2Fa/migrations/mig%2Fa".to_string())
    );
}
