mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn create_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .workspaces()
        .create("repo/a", json!({}))
        .await
        .unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/repos/repo%2Fa/workspaces".to_string()));
}

#[tokio::test]
async fn get_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.workspaces().get("ws/a").await.unwrap();
    assert!(request_keys(&mock).contains(&"GET /api/v1/workspaces/ws%2Fa".to_string()));
}

#[tokio::test]
async fn close_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.workspaces().close("ws/a", json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/workspaces/ws%2Fa/close".to_string()));
}
