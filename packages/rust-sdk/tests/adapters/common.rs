#![allow(dead_code)]
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use serde_json::json;
use treedx_sdk::{
    Transport, TreeDxClient, TreeDxConfig, TreeDxRequest, TreeDxResponse, TreeDxResult,
};

#[derive(Default)]
pub struct MockTransport {
    pub requests: Mutex<Vec<TreeDxRequest>>,
}

#[async_trait]
impl Transport for MockTransport {
    async fn request(&self, request: TreeDxRequest) -> TreeDxResult<TreeDxResponse> {
        self.requests.lock().unwrap().push(request);
        Ok(TreeDxResponse {
            status: 200,
            headers: BTreeMap::new(),
            data: json!({ "ok": true }),
        })
    }
}

pub fn client_with_mock(mock: Arc<MockTransport>) -> TreeDxClient {
    TreeDxClient::with_transport(
        TreeDxConfig {
            base_url: "http://localhost:4000".to_string(),
            ..Default::default()
        },
        mock,
    )
}

pub fn request_keys(mock: &MockTransport) -> Vec<String> {
    mock.requests
        .lock()
        .unwrap()
        .iter()
        .map(|request| format!("{} {}", request.method.as_str(), request.path))
        .collect()
}
