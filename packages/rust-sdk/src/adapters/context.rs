use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct ContextAdapter {
    transport: Arc<dyn Transport>,
}

impl ContextAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn build(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/context/build", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn parse(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/context/parse-ctx", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }
}
