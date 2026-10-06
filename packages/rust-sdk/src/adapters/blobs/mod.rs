use std::collections::BTreeMap;
use std::sync::Arc;

use bytes::Bytes;
use serde_json::Value;

use crate::adapters::common::{binary_request, json_request, segment};
use crate::error::TreeDxResult;
use crate::transport::{Transport, TreeDxHttpMethod};

#[derive(Clone)]
pub struct BlobsAdapter {
    transport: Arc<dyn Transport>,
}

impl BlobsAdapter {
    pub fn new(transport: Arc<dyn Transport>) -> Self {
        Self { transport }
    }

    pub async fn read(&self, repo_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/repos/{}/blobs/read", segment(repo_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn write(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/workspaces/{}/blobs/write", segment(workspace_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn delete(&self, workspace_id: &str, body: Value) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/workspaces/{}/blobs/delete", segment(workspace_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn download(
        &self,
        workspace_id: &str,
        query: BTreeMap<String, String>,
    ) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Get,
            format!(
                "/api/v1/workspaces/{}/blobs/download",
                segment(workspace_id)
            ),
            None,
            Some(query),
        )
        .await
    }

    pub async fn upload(
        &self,
        workspace_id: &str,
        bytes: Bytes,
        query: BTreeMap<String, String>,
    ) -> TreeDxResult<Value> {
        binary_request(
            &self.transport,
            TreeDxHttpMethod::Put,
            format!("/api/v1/workspaces/{}/blobs/upload", segment(workspace_id)),
            bytes,
            Some(query),
        )
        .await
    }

    pub async fn create_multipart_upload(
        &self,
        workspace_id: &str,
        body: Value,
    ) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!("/api/v1/workspaces/{}/blobs/uploads", segment(workspace_id)),
            Some(body),
            None,
        )
        .await
    }

    pub async fn upload_part(
        &self,
        workspace_id: &str,
        upload_id: &str,
        part_number: u32,
        bytes: Bytes,
    ) -> TreeDxResult<Value> {
        binary_request(
            &self.transport,
            TreeDxHttpMethod::Put,
            format!(
                "/api/v1/workspaces/{}/blobs/uploads/{}/parts/{}",
                segment(workspace_id),
                segment(upload_id),
                part_number
            ),
            bytes,
            None,
        )
        .await
    }

    pub async fn complete_multipart_upload(
        &self,
        workspace_id: &str,
        upload_id: &str,
        body: Value,
    ) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Post,
            format!(
                "/api/v1/workspaces/{}/blobs/uploads/{}/complete",
                segment(workspace_id),
                segment(upload_id)
            ),
            Some(body),
            None,
        )
        .await
    }

    pub async fn abort_multipart_upload(
        &self,
        workspace_id: &str,
        upload_id: &str,
    ) -> TreeDxResult<Value> {
        json_request(
            &self.transport,
            TreeDxHttpMethod::Delete,
            format!(
                "/api/v1/workspaces/{}/blobs/uploads/{}",
                segment(workspace_id),
                segment(upload_id)
            ),
            None,
            None,
        )
        .await
    }
}
