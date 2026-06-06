use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDbResult;
use crate::transport::{Transport, TreeDbHttpMethod};

#[derive(Clone)]
pub struct PolicyAdapter {
    transport: Arc<dyn Transport>,
}

impl PolicyAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn capabilities(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/policy/capabilities",
            None,
            None,
        )
        .await
    }
    pub async fn grants(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/policy/grants",
            None,
            None,
        )
        .await
    }
    pub async fn create_grant(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/policy/grants",
            Some(body),
            None,
        )
        .await
    }
    pub async fn refresh(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/policy/refresh",
            body,
            None,
        )
        .await
    }
}
