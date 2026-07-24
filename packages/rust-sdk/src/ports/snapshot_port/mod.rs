use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait SnapshotPort: Send + Sync {
    async fn build(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn get(&self, repo_id: &str, snapshot_id: &str) -> TreeDxResult<Value>;
}
