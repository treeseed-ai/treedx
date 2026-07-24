use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct SnapshotsAdapter {
    transport: Arc<dyn Transport>,
}

impl SnapshotsAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn build(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/snapshots/build", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn get(&self, repo_id: &str, snapshot_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!(
                "/api/v1/repos/{}/snapshots/{}",
                segment(repo_id),
                segment(snapshot_id)
            ),
            None,
            None,
        )
        .await
    }
}
