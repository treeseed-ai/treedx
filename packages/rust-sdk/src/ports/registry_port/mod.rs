use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait RegistryPort: Send + Sync {
    async fn local_node(&self) -> TreeDxResult<Value>;
    async fn nodes(&self) -> TreeDxResult<Value>;
    async fn get_placement(&self, repo_id: &str) -> TreeDxResult<Value>;
    async fn set_placement(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
}
