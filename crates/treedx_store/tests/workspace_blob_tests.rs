use base64::Engine;
use chrono::Utc;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn workspace_file_overlay_accepts_base64_binary_content() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();

    let bytes = vec![0, 159, 146, 150, 255];
    let content_base64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    let expected_hash = hash_bytes(&bytes);

    let record = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_1".into(),
            path: "assets/logo.bin".into(),
            op: "put".into(),
            encoding: Some("base64".into()),
            content_base64: Some(content_base64),
            expected_sha: None,
            expected_content_hash: Some(expected_hash.clone()),
            base_sha: None,
            content_type: Some("application/octet-stream".into()),
        },
    )
    .unwrap();

    assert_eq!(record.encoding.as_deref(), Some("base64"));
    assert_eq!(record.content_hash.as_deref(), Some(expected_hash.as_str()));
    assert_eq!(
        record.content_type.as_deref(),
        Some("application/octet-stream")
    );
    assert_eq!(record.size, bytes.len() as u64);
    assert_eq!(
        read_workspace_file_content(dir.path(), &record)
            .unwrap()
            .unwrap(),
        bytes
    );
}

#[test]
fn workspace_file_overlay_rejects_malformed_base64_and_hash_mismatch() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();

    let malformed = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_1".into(),
            path: "assets/bad.bin".into(),
            op: "put".into(),
            encoding: Some("base64".into()),
            content_base64: Some("not base64".into()),
            expected_sha: None,
            expected_content_hash: None,
            base_sha: None,
            content_type: None,
        },
    );
    assert!(matches!(malformed, Err(StoreError::Validation(_))));

    let mismatch = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_1".into(),
            path: "assets/mismatch.bin".into(),
            op: "put".into(),
            encoding: Some("base64".into()),
            content_base64: Some(base64::engine::general_purpose::STANDARD.encode([1, 2, 3])),
            expected_sha: None,
            expected_content_hash: Some("blake3:bad".into()),
            base_sha: None,
            content_type: None,
        },
    );
    assert!(matches!(mismatch, Err(StoreError::Conflict(_))));
}

#[test]
fn old_utf8_workspace_records_still_deserialize() {
    let json = serde_json::json!({
        "id": "wsfile_1",
        "workspaceId": "ws_1",
        "path": "docs/readme.md",
        "op": "put",
        "encoding": "utf8",
        "contentHash": "blake3:test",
        "contentPath": "/tmp/content",
        "expectedSha": null,
        "baseSha": null,
        "size": 5,
        "updatedAt": Utc::now()
    });

    let record: WorkspaceFileRecord = serde_json::from_value(json).unwrap();
    assert_eq!(record.expected_content_hash, None);
    assert_eq!(record.content_type, None);
}
