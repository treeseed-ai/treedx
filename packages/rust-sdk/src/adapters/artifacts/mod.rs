use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct ArtifactsAdapter {
    transport: Arc<dyn Transport>,
}

impl ArtifactsAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn export(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/artifacts/export", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn list(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}/artifacts", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn get(&self, repo_id: &str, artifact_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!(
                "/api/v1/repos/{}/artifacts/{}",
                segment(repo_id),
                segment(artifact_id)
            ),
            None,
            None,
        )
        .await
    }

    pub async fn delete(&self, repo_id: &str, artifact_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Delete,
            format!(
                "/api/v1/repos/{}/artifacts/{}",
                segment(repo_id),
                segment(artifact_id)
            ),
            None,
            None,
        )
        .await
    }
}
