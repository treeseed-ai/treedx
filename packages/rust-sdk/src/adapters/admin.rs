use std::sync::Arc;

use serde_json::Value;

use crate::adapters::common::json_request;
use crate::error::TreeDbResult;
use crate::transport::{Transport, TreeDbHttpMethod};

#[derive(Clone)]
pub struct AdminAdapter {
    transport: Arc<dyn Transport>,
}

impl AdminAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn deep_health(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/admin/health/deep",
            None,
            None,
        )
        .await
    }
    pub async fn storage_health(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/admin/storage/health",
            None,
            None,
        )
        .await
    }
    pub async fn storage_check(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/check",
            body,
            None,
        )
        .await
    }
    pub async fn storage_recover(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/recover",
            body,
            None,
        )
        .await
    }
    pub async fn storage_compact(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/compact",
            body,
            None,
        )
        .await
    }
    pub async fn storage_backup(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/backup",
            body,
            None,
        )
        .await
    }
    pub async fn storage_migrations(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/admin/storage/migrations",
            None,
            None,
        )
        .await
    }
    pub async fn storage_migration_plan(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/migrations/plan",
            Some(body),
            None,
        )
        .await
    }
    pub async fn storage_migration_apply(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/migrations/apply",
            Some(body),
            None,
        )
        .await
    }
    pub async fn storage_migration_rollback(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/migrations/rollback",
            Some(body),
            None,
        )
        .await
    }
    pub async fn storage_restore_verify(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/restore/verify",
            Some(body),
            None,
        )
        .await
    }
    pub async fn storage_restore(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/storage/restore",
            Some(body),
            None,
        )
        .await
    }
    pub async fn quarantined_workspaces(&self) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/admin/workspaces/quarantined",
            None,
            None,
        )
        .await
    }
    pub async fn cleanup_artifacts(&self, body: Option<Value>) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/artifacts/cleanup",
            body,
            None,
        )
        .await
    }
    pub async fn import_local_repo(&self, body: Value) -> TreeDbResult<Value> {
        json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/admin/repos/import-local",
            Some(body),
            None,
        )
        .await
    }
}
