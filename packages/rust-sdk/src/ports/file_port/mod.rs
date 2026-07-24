use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait FilePort: Send + Sync {
    async fn tree(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn read(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn write(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn patch(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn delete(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn search(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn status(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn diff(&self, workspace_id: &str) -> TreeDxResult<Value>;
    async fn commit(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value>;
}
