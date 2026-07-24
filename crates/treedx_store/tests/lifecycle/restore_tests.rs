use tempfile::tempdir;
use treedx_store::*;

#[test]
fn backup_checksum_changes_when_archive_is_tampered() {
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
            include: vec!["catalog".to_string()],
            verify: true,
        },
    )
    .unwrap();

    let backup_path = dir
        .path()
        .join("recovery")
        .join("backups")
        .join(&backup.backup_id)
        .join("treedx-backup.tar.zst");
    let mut bytes = std::fs::read(&backup_path).unwrap();
    bytes.push(0xff);

    assert_ne!(hash_bytes(&bytes), backup.checksum);
}
