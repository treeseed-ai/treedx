use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::{json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct FederationInternalAdapter {
    transport: Arc<dyn Transport>,
}

impl FederationInternalAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn health(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/internal/federation/health",
            None,
            None,
        )
        .await
    }
    pub async fn proxy(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/internal/federation/proxy",
            Some(body),
            None,
        )
        .await
    }
    pub async fn export_mirror(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/internal/federation/repos/{}/mirror/export",
                segment(repo_id)
            ),
            Some(body),
            None,
        )
        .await
    }
    pub async fn import_mirror(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/internal/federation/repos/{}/mirror/import",
                segment(repo_id)
            ),
            Some(body),
            None,
        )
        .await
    }
}
