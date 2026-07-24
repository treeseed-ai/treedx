use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct WorkspacesAdapter {
    transport: Arc<dyn Transport>,
}

impl WorkspacesAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn create(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/workspaces", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn get(&self, workspace_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/workspaces/{}", segment(workspace_id)),
            None,
            None,
        )
        .await
    }

    pub async fn close(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/workspaces/{}/close", segment(workspace_id)),
            Some(body),
            None,
        )
        .await
    }
}
