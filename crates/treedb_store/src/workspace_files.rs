use crate::catalog::{get_record, list_records, put_record};
use crate::error::StoreError;
use crate::ids::workspace_file_id;
use crate::types::{WorkspaceFileInput, WorkspaceFileRecord};
use base64::Engine;
use chrono::Utc;
use std::path::Path;

pub fn put_workspace_file(
    data_dir: &Path,
    input: WorkspaceFileInput,
) -> Result<WorkspaceFileRecord, StoreError> {
    if input.workspace_id.trim().is_empty() {
        return Err(StoreError::Validation(
            "workspaceId is required".to_string(),
        ));
    }
    let path = input.path.trim_matches('/').to_string();
    if path.is_empty() {
        return Err(StoreError::Validation("path is required".to_string()));
    }
    if input.op != "put" && input.op != "delete" {
        return Err(StoreError::Validation(
            "workspace file op must be put or delete".to_string(),
        ));
    }

    let id = workspace_file_id(&input.workspace_id, &path);
    let now = Utc::now();
    let (content_hash, content_path, size) = if input.op == "put" {
        if !matches!(input.encoding.as_deref(), Some("utf8") | Some("base64")) {
            return Err(StoreError::Validation(
                "workspace file encoding must be utf8 or base64".to_string(),
            ));
        }
        let content_base64 = input.content_base64.as_deref().ok_or_else(|| {
            StoreError::Validation("contentBase64 is required for put".to_string())
        })?;
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(content_base64)
            .map_err(|err| StoreError::Validation(format!("invalid contentBase64: {err}")))?;
        let hash_hex = blake3::hash(&bytes).to_hex().to_string();
        let content_hash = format!("blake3:{hash_hex}");
        if let Some(expected_hash) = input.expected_content_hash.as_deref() {
            if expected_hash != content_hash {
                return Err(StoreError::Conflict(
                    "expectedContentHash does not match.".to_string(),
                ));
            }
        }
        let blob_dir = data_dir
            .join("workspaces/active")
            .join(&input.workspace_id)
            .join("overlay/blobs");
        std::fs::create_dir_all(&blob_dir)?;
        let blob_path = blob_dir.join(&hash_hex);
        std::fs::write(&blob_path, &bytes)?;
        (
            Some(content_hash),
            Some(blob_path.display().to_string()),
            bytes.len() as u64,
        )
    } else {
        (None, None, 0)
    };

    let record = WorkspaceFileRecord {
        id: id.clone(),
        workspace_id: input.workspace_id,
        path,
        op: input.op,
        encoding: input.encoding,
        content_hash,
        content_path,
        expected_sha: input.expected_sha,
        expected_content_hash: input.expected_content_hash,
        base_sha: input.base_sha,
        content_type: input.content_type,
        size,
        updated_at: now,
    };

    put_record(
        data_dir,
        "workspaces/files.tdb",
        "workspace_file",
        &id,
        &record,
    )?;
    Ok(record)
}

pub fn get_workspace_file(
    data_dir: &Path,
    workspace_id: &str,
    path: &str,
) -> Result<Option<WorkspaceFileRecord>, StoreError> {
    let id = workspace_file_id(workspace_id, path.trim_matches('/'));
    get_record(data_dir, "workspaces/files.tdb", "workspace_file", &id)
}

pub fn list_workspace_files(
    data_dir: &Path,
    workspace_id: &str,
) -> Result<Vec<WorkspaceFileRecord>, StoreError> {
    let mut records =
        list_records::<WorkspaceFileRecord>(data_dir, "workspaces/files.tdb", "workspace_file")?
            .into_iter()
            .filter(|record| record.workspace_id == workspace_id)
            .collect::<Vec<_>>();
    records.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(records)
}

pub fn read_workspace_file_content(
    _data_dir: &Path,
    record: &WorkspaceFileRecord,
) -> Result<Option<Vec<u8>>, StoreError> {
    let Some(content_path) = record.content_path.as_deref() else {
        return Ok(None);
    };
    Ok(Some(std::fs::read(content_path)?))
}
