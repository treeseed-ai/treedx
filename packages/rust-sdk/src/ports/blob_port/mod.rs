use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait BlobPort: Send + Sync {
    async fn read(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn write(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn delete(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
}
