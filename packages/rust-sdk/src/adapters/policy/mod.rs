use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct PolicyAdapter {
    transport: Arc<dyn Transport>,
}

impl PolicyAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn capabilities(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/policy/capabilities",
            None,
            None,
        )
        .await
    }
    pub async fn grants(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/policy/grants",
            None,
            None,
        )
        .await
    }
    pub async fn create_grant(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/policy/grants",
            Some(body),
            None,
        )
        .await
    }
    pub async fn refresh(&self, body: Option<Value>) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/policy/refresh",
            body,
            None,
        )
        .await
    }
}
