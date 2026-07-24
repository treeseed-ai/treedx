use crate::error::TreeDxResult;
use async_trait::async_trait;
use serde_json::Value;

#[async_trait]
pub trait QueryPort: Send + Sync {
    async fn read_file(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn list_paths(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn search_files(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
    async fn repository(&self, repo_id: &str, body: Value) -> TreeDxResult<Value>;
}
