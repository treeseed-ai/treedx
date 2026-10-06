mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn register_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.repositories().register(json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/repos/register".to_string()));
}

#[tokio::test]
async fn get_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.repositories().get("repo/a").await.unwrap();
    assert!(request_keys(&mock).contains(&"GET /api/v1/repos/repo%2Fa".to_string()));
}

#[tokio::test]
async fn refs_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.repositories().refs("repo/a").await.unwrap();
    assert!(request_keys(&mock).contains(&"GET /api/v1/repos/repo%2Fa/refs".to_string()));
}
