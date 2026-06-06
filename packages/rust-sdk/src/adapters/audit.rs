use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDbResult;
use crate::transport::{Transport, TreeDbHttpMethod};

#[derive(Clone)]
pub struct AuditAdapter {
    transport: Arc<dyn Transport>,
}

impl AuditAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn events(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/audit/events",
            None,
            None,
        )
        .await
    }
}
