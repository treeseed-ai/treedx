use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait FederationPort: Send + Sync {
    async fn plan(&self, body: Value) -> TreeDxResult<Value>;
    async fn search(&self, body: Value) -> TreeDxResult<Value>;
    async fn query(&self, body: Value) -> TreeDxResult<Value>;
    async fn context_build(&self, body: Value) -> TreeDxResult<Value>;
    async fn graph_query(&self, body: Value) -> TreeDxResult<Value>;
}
