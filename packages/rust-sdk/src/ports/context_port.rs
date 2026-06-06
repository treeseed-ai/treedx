use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait ContextPort: Send + Sync {
    async fn build(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn parse(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
}
