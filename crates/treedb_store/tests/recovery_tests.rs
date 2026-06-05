use std::io::Write;
use tempfile::tempdir;
use treedb_store::*;

#[test]
fn corrupt_payload_checksum_returns_recovery_error() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    put_repository(
        dir.path(),
        RepositoryInput {
            name: "demo".to_string(),
            repository_name: Some("demo".to_string()),
            local_path: Some("/var/lib/treedb/repos/bare/demo.git".to_string()),
            storage_relative_path: Some("repositories/demo".to_string()),
            default_ref: None,
            remote_url: None,
        },
    )
    .unwrap();
    let path = dir.path().join("catalog/repositories.tdb");
    let mut raw = std::fs::read_to_string(&path).unwrap();
    raw = raw.replace("\"name\":\"demo\"", "\"name\":\"tampered\"");
    let mut file = std::fs::File::create(&path).unwrap();
    file.write_all(raw.as_bytes()).unwrap();
    let err = list_repositories(dir.path()).unwrap_err();
    assert_eq!(err.code(), "checksum_mismatch");
}

#[test]
fn compaction_preserves_latest_records_and_skips_audit_logs() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    for name in ["one", "two"] {
        put_repository(
            dir.path(),
            RepositoryInput {
                name: name.to_string(),
                repository_name: Some(name.to_string()),
                local_path: Some(format!("/var/lib/treedb/repos/bare/{name}.git")),
                storage_relative_path: Some(format!("repositories/{name}")),
                default_ref: None,
                remote_url: None,
            },
        )
        .unwrap();
    }
    append_audit_event(
        dir.path(),
        AuditEventInput {
            event_type: "storage.test".to_string(),
            actor_id: None,
            tenant_id: None,
            repo_id: None,
            node_id: None,
            workspace_id: None,
            operation: None,
            status: Some("ok".to_string()),
            request_id: None,
            requested_scope: None,
            effective_scope: None,
            data: serde_json::json!({}),
        },
    )
    .unwrap();
    let audit_before = std::fs::metadata(dir.path().join("audit/events.tdb"))
        .unwrap()
        .len();

    let result = compact_storage(
        dir.path(),
        StorageCompactInput {
            logs: vec![],
            dry_run: false,
            backup_before: true,
        },
    )
    .unwrap();

    assert_eq!(result.status, "ok");
    assert!(result.backup_id.is_some());
    assert!(result
        .files
        .iter()
        .any(|file| file.file == "catalog/repositories.tdb"));
    assert_eq!(list_repositories(dir.path()).unwrap().len(), 2);
    assert_eq!(
        std::fs::metadata(dir.path().join("audit/events.tdb"))
            .unwrap()
            .len(),
        audit_before
    );
}

#[test]
fn backup_archive_verifies_and_uses_logical_uri() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let backup = create_backup(
        dir.path(),
        StorageBackupInput {
            include: vec!["catalog".to_string(), "snapshots".to_string()],
            verify: true,
        },
    )
    .unwrap();

    assert_eq!(backup.format, "tar.zst");
    assert!(backup.uri.starts_with("treedb://backup/"));
    assert!(backup.checksum.starts_with("blake3:"));
    assert!(backup.byte_length > 0);
    assert!(backup.verified);
    assert!(!serde_json::to_string(&backup)
        .unwrap()
        .contains(dir.path().to_string_lossy().as_ref()));
}
