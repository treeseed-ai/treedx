use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait RepositoryPort: Send + Sync {
    async fn register(&self, body: Value) -> TreeDxResult<Value>;
    async fn list(&self) -> TreeDxResult<Value>;
    async fn create(&self, body: Value) -> TreeDxResult<Value>;
    async fn get(&self, repo_id: &str) -> TreeDxResult<Value>;
}
