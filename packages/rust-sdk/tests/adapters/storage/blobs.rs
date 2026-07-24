mod common;
use common::{MockTransport, client_with_mock, request_keys};
use serde_json::json;
use std::sync::Arc;

#[tokio::test]
async fn read_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.blobs().read("repo/a", json!({})).await.unwrap();
    assert!(request_keys(&mock).contains(&"POST /api/v1/repos/repo%2Fa/blobs/read".to_string()));
}

#[tokio::test]
async fn write_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client.blobs().write("ws/a", json!({})).await.unwrap();
    assert!(
        request_keys(&mock).contains(&"POST /api/v1/workspaces/ws%2Fa/blobs/write".to_string())
    );
}

#[tokio::test]
async fn download_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .blobs()
        .download("ws/a", Default::default())
        .await
        .unwrap();
    assert!(
        request_keys(&mock).contains(&"GET /api/v1/workspaces/ws%2Fa/blobs/download".to_string())
    );
}

#[tokio::test]
async fn upload_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .blobs()
        .upload("ws/a", bytes::Bytes::from_static(b"x"), Default::default())
        .await
        .unwrap();
    assert!(
        request_keys(&mock).contains(&"PUT /api/v1/workspaces/ws%2Fa/blobs/upload".to_string())
    );
}

#[tokio::test]
async fn multipart_constructs_expected_request() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock.clone());
    client
        .blobs()
        .create_multipart_upload("ws/a", json!({}))
        .await
        .unwrap();
    client
        .blobs()
        .upload_part("ws/a", "up/a", 3, bytes::Bytes::from_static(b"x"))
        .await
        .unwrap();
    client
        .blobs()
        .complete_multipart_upload("ws/a", "up/a", json!({}))
        .await
        .unwrap();
    client
        .blobs()
        .abort_multipart_upload("ws/a", "up/a")
        .await
        .unwrap();
    assert!(
        request_keys(&mock)
            .contains(&"DELETE /api/v1/workspaces/ws%2Fa/blobs/uploads/up%2Fa".to_string())
    );
}
