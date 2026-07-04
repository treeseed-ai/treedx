use std::io::Write;
use tempfile::tempdir;
use treedx_store::*;

#[test]
fn storage_security_reports_logical_files_only_and_preserves_audit_logs() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    append_audit_event(
        dir.path(),
        AuditEventInput {
            event_type: "security.audit".to_string(),
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

    let audit_before = std::fs::read_to_string(dir.path().join("audit/events.tdb")).unwrap();
    let logs = list_tdb_logs(dir.path()).unwrap();
    assert!(logs.iter().any(|file| file == "audit/events.tdb"));
    assert!(logs
        .iter()
        .all(|file| !file.contains(dir.path().to_string_lossy().as_ref())));

    let compact = compact_storage(
        dir.path(),
        StorageCompactInput {
            logs: vec![],
            plan: false,
            backup_before: false,
        },
    )
    .unwrap();
    assert!(compact
        .files
        .iter()
        .all(|file| !file.file.starts_with("audit/")));
    assert_eq!(
        std::fs::read_to_string(dir.path().join("audit/events.tdb")).unwrap(),
        audit_before
    );
}

#[test]
fn malformed_record_checksum_is_rejected() {
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
            name: "checksum-demo".to_string(),
            repository_name: Some("checksum-demo".to_string()),
            local_path: Some("/var/lib/treedx/repos/bare/checksum-demo.git".to_string()),
            storage_relative_path: Some("repositories/checksum-demo".to_string()),
            default_ref: None,
            remote_url: None,
        },
    )
    .unwrap();
    let path = dir.path().join("catalog/repositories.tdb");
    let mut raw = std::fs::read_to_string(&path).unwrap();
    raw = raw.replace("checksum-demo", "tampered-demo");
    let mut file = std::fs::File::create(&path).unwrap();
    file.write_all(raw.as_bytes()).unwrap();

    let error = list_repositories(dir.path()).unwrap_err();
    assert_eq!(error.code(), "checksum_mismatch");
}
