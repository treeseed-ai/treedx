use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait WorkspacePort: Send + Sync {
    async fn create(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn get(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn close(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
}
