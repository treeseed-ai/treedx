use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait MirrorPort: Send + Sync {
    async fn list(&self, repo_id: &str) -> TreeDxResult<Value>;
    async fn upsert(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn sync(&self, repo_id: &str, mirror_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn health(&self, repo_id: &str, mirror_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn promote(&self, repo_id: &str, mirror_id: &str, body: Value) -> TreeDxResult<Value>;
}
