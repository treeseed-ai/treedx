mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn tree_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .files()
        .tree("ws/a", Default::default())
        .await
        .unwrap();
    assert!(request_keys(&mock).contains(&"GET /api/v1/workspaces/ws%2Fa/tree".to_string()));
}

#[tokio::test]
async fn write_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.files().write("ws/a", json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"PUT /api/v1/workspaces/ws%2Fa/files".to_string()));
}

#[tokio::test]
async fn patch_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.files().patch("ws/a", json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"PATCH /api/v1/workspaces/ws%2Fa/files".to_string()));
}

#[tokio::test]
async fn delete_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .files()
        .delete("ws/a", Default::default())
        .await
        .unwrap();
    assert!(request_keys(&mock).contains(&"DELETE /api/v1/workspaces/ws%2Fa/files".to_string()));
}

#[tokio::test]
async fn commit_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.files().commit("ws/a", json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/workspaces/ws%2Fa/commit".to_string()));
}
