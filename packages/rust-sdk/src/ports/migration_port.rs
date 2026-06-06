use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait MigrationPort: Send + Sync {
    async fn create(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn get(&self, repo_id: &str, migration_id: &str) -> TreeDxResult<Value>;
}
