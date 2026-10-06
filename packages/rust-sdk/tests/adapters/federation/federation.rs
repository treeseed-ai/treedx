mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.federation().plan(json!({})).await.unwrap();
    client.federation().search(json!({})).await.unwrap();
    client.federation().query(json!({})).await.unwrap();
    client.federation().context_build(json!({})).await.unwrap();
    client.federation().graph_query(json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/graph/query".to_string()));
}
