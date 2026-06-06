use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait ArtifactPort: Send + Sync {
    async fn export(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn list(&self, repo_id: &str) -> TreeDxResult<Value>;
    async fn get(&self, repo_id: &str, artifact_id: &str) -> TreeDxResult<Value>;
    async fn delete(&self, repo_id: &str, artifact_id: &str) -> TreeDxResult<Value>;
}
