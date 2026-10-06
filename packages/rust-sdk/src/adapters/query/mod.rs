use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct QueryAdapter {
    transport: Arc<dyn Transport>,
}

impl QueryAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn read_file(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/files/read", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn list_paths(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/paths/list", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn search_files(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/files/search", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn repository(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/query", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }
}
