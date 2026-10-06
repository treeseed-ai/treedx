use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct FederationAdapter {
    transport: Arc<dyn Transport>,
}

impl FederationAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn plan(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/federation/query/plan",
            Some(body),
            None,
        )
        .await
    }

    pub async fn search(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/search",
            Some(body),
            None,
        )
        .await
    }

    pub async fn query(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/query",
            Some(body),
            None,
        )
        .await
    }

    pub async fn context_build(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/context/build",
            Some(body),
            None,
        )
        .await
    }

    pub async fn graph_query(&self, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            "/api/v1/graph/query",
            Some(body),
            None,
        )
        .await
    }
}
