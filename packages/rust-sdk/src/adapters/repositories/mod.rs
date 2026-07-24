use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct RepositoriesAdapter {
    transport: Arc<dyn Transport>,
}

impl RepositoriesAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn register(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/repos/register",
            Some(body),
            None,
        )
        .await
    }

    pub async fn list(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/repos",
            None,
            None,
        )
        .await
    }

    pub async fn create(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/repos",
            Some(body),
            None,
        )
        .await
    }

    pub async fn get(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn status(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}/status", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn refs(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}/refs", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn remotes(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/repos/{}/remotes", segment(repo_id)),
            None,
            None,
        )
        .await
    }
}
