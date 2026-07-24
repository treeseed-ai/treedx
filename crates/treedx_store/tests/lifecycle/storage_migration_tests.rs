use tempfile::tempdir;
use treedx_store::*;

#[test]
fn compaction_plan_is_deterministic_and_non_mutating() {
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
            name: "migration-demo".to_string(),
            repository_name: Some("migration-demo".to_string()),
            local_path: Some("/var/lib/treedx/repos/bare/migration-demo.git".to_string()),
            storage_relative_path: Some("repositories/migration-demo".to_string()),
            default_ref: None,
            remote_url: None,
        },
    )
    .unwrap();

    let before = std::fs::read_to_string(dir.path().join("catalog/repositories.tdb")).unwrap();
    let one = compact_storage(
        dir.path(),
        StorageCompactInput {
            logs: vec!["catalog/repositories.tdb".to_string()],
            plan: true,
            backup_before: false,
        },
    )
    .unwrap();
    let two = compact_storage(
        dir.path(),
        StorageCompactInput {
            logs: vec!["catalog/repositories.tdb".to_string()],
            plan: true,
            backup_before: false,
        },
    )
    .unwrap();
    let after = std::fs::read_to_string(dir.path().join("catalog/repositories.tdb")).unwrap();

    assert_eq!(before, after);
    assert_eq!(one.files.len(), two.files.len());
    assert_eq!(one.files[0].file, "catalog/repositories.tdb");
}
