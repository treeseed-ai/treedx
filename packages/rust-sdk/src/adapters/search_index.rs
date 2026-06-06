use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDbResult;
use crate::transport::{Transport, TreeDbHttpMethod};

#[derive(Clone)]
pub struct SearchIndexAdapter {
    transport: Arc<dyn Transport>,
}

impl SearchIndexAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn status(&self, repo_id: &str) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            format!("/api/v1/repos/{}/search/index/status", segment(repo_id)),
            None,
            None,
        )
        .await
    }
    pub async fn refresh(&self, repo_id: &str, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            format!("/api/v1/repos/{}/search/index/refresh", segment(repo_id)),
            body,
            None,
        )
        .await
    }
    pub async fn compact(&self, repo_id: &str, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            format!("/api/v1/repos/{}/search/index/compact", segment(repo_id)),
            body,
            None,
        )
        .await
    }
}
