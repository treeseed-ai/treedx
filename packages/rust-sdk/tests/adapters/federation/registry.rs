mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.registry().local_node().await.unwrap();
    client.registry().nodes().await.unwrap();
    client.registry().get_placement("repo/a").await.unwrap();
    client
        .registry()
        .set_placement("repo/a", json!({}))
        .await
        .unwrap();
    assert!(
        request_keys(&mock).contains(&"POST /api/v1/registry/repos/repo%2Fa/placement".to_string())
    );
}
