use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct ObservabilityAdapter {
    transport: Arc<dyn Transport>,
}

impl ObservabilityAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn health(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/health",
            None,
            None,
        )
        .await
    }

    pub async fn ready(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/ready",
            None,
            None,
        )
        .await
    }

    pub async fn deep_health(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/health/deep",
            None,
            None,
        )
        .await
    }

    pub async fn metrics(&self) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            "/api/v1/metrics",
            None,
            None,
        )
        .await
    }
}
