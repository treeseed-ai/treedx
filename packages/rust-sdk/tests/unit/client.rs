use std::sync::Arc;

#[path = "../adapters/mock_transport.rs"]
mod mock_transport;

use mock_transport::{MockTransport, client_with_mock};
use treedx::{TreeDxClient, TreeDxConfig};

#[tokio::test]
async fn client_exposes_all_module_adapters() {
    let mock = Arc::new(MockTransport::default());
    let client = client_with_mock(mock);
    let _ = client.repositories();
    let _ = client.workspaces();
    let _ = client.files();
    let _ = client.blobs();
    let _ = client.query();
    let _ = client.graph();
    let _ = client.context();
    let _ = client.federation();
    let _ = client.registry();
    let _ = client.snapshots();
    let _ = client.artifacts();
    let _ = client.mirrors();
    let _ = client.migrations();
    let _ = client.exec();
    let _ = client.observability();
}

#[tokio::test]
async fn custom_transport_is_used() {
    let mock = Arc::new(MockTransport::default());
    let client = TreeDxClient::with_transport(
        TreeDxConfig {
            base_url: "http://localhost:4000".to_string(),
            ..Default::default()
        },
        mock.clone(),
    );
    client.health().await.unwrap();
    assert_eq!(mock.requests.lock().unwrap().len(), 1);
}
