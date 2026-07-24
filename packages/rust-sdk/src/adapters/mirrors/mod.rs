use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct MirrorsAdapter {
    transport: Arc<dyn Transport>,
}

impl MirrorsAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn list(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}/mirrors", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn upsert(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/mirrors", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn sync(&self, repo_id: &str, mirror_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/repos/{}/mirrors/{}/sync",
                segment(repo_id),
                segment(mirror_id)
            ),
            Some(body),
            None,
        )
        .await
    }

    pub async fn health(&self, repo_id: &str, mirror_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/repos/{}/mirrors/{}/health",
                segment(repo_id),
                segment(mirror_id)
            ),
            Some(body),
            None,
        )
        .await
    }

    pub async fn promote(
        &self,
        repo_id: &str,
        mirror_id: &str,
        body: Value,
    ) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/repos/{}/mirrors/{}/promote",
                segment(repo_id),
                segment(mirror_id)
            ),
            Some(body),
            None,
        )
        .await
    }
}
