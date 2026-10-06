use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct RegistryAdapter {
    transport: Arc<dyn Transport>,
}

impl RegistryAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn local_node(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/node",
            None,
            None,
        )
        .await
    }

    pub async fn nodes(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/registry/nodes",
            None,
            None,
        )
        .await
    }

    pub async fn get_placement(&self, repo_id: &str) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!("/api/v1/registry/repos/{}/placement", segment(repo_id)),
            None,
            None,
        )
        .await
    }

    pub async fn set_placement(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/registry/repos/{}/placement", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }
}
