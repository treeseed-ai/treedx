use tempfile::tempdir;
use treedb_store::*;

#[test]
fn backup_result_uses_logical_uri_and_verifies_archive() {
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
            name: "backup-demo".to_string(),
            local_path: "/var/lib/treedb/repos/bare/backup-demo.git".to_string(),
            default_ref: None,
            remote_url: None,
        },
    )
    .unwrap();

    let backup = create_backup(
        dir.path(),
        StorageBackupInput {
            include: vec!["catalog".to_string(), "policy".to_string()],
            verify: true,
        },
    )
    .unwrap();

    assert!(backup.backup_id.starts_with("backup_"));
    assert_eq!(backup.uri, format!("treedb://backup/{}", backup.backup_id));
    assert!(backup.checksum.starts_with("blake3:"));
    assert!(backup.verified);
    assert!(!serde_json::to_string(&backup)
        .unwrap()
        .contains(dir.path().to_string_lossy().as_ref()));
}
