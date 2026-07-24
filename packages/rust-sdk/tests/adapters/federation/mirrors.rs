mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn all_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.mirrors().list("repo/a").await.unwrap();
    client.mirrors().upsert("repo/a", json!({})).await.unwrap();
    client
        .mirrors()
        .sync("repo/a", "mir/a", json!({}))
        .await
        .unwrap();
    client
        .mirrors()
        .health("repo/a", "mir/a", json!({}))
        .await
        .unwrap();
    client
        .mirrors()
        .promote("repo/a", "mir/a", json!({}))
        .await
        .unwrap();
    assert!(
        request_keys(&mock)
            .contains(&"POST /api/v1/repos/repo%2Fa/mirrors/mir%2Fa/promote".to_string())
    );
}
