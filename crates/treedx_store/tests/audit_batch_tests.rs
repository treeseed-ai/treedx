use tempfile::tempdir;
use treedx_store::*;

#[test]
fn batch_audit_append_writes_replayable_events() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    let records = append_audit_events(
        dir.path(),
        vec![
            input("repo.registered", "repo_a"),
            input("repo.files_read", "repo_a"),
            input("graph.queried", "repo_b"),
        ],
    )
    .unwrap();

    assert_eq!(records.len(), 3);

    let listed = list_audit_events(
        dir.path(),
        AuditQuery {
            actor_id: None,
            tenant_id: None,
            repo_id: Some("repo_a".to_string()),
            event_type: None,
            limit: Some(100),
        },
    )
    .unwrap();

    assert_eq!(listed.len(), 2);
    assert!(listed
        .iter()
        .all(|record| record.repo_id.as_deref() == Some("repo_a")));
}

#[test]
fn batch_audit_append_preserves_checksum_validation() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    append_audit_events(dir.path(), vec![input("repo.registered", "repo_a")]).unwrap();

    let path = dir.path().join("audit/events.tdb");
    let mut contents = std::fs::read_to_string(&path).unwrap();
    contents = contents.replace("repo.registered", "repo.tampered");
    std::fs::write(path, contents).unwrap();

    let error = list_audit_events(
        dir.path(),
        AuditQuery {
            actor_id: None,
            tenant_id: None,
            repo_id: None,
            event_type: None,
            limit: Some(100),
        },
    )
    .unwrap_err();

    assert_eq!(error.code(), "checksum_mismatch");
}

#[test]
fn concurrent_audit_appends_remain_replayable() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();

    std::thread::scope(|scope| {
        for worker in 0..16 {
            let root = dir.path().to_path_buf();
            scope.spawn(move || {
                for batch in 0..25 {
                    append_audit_events(
                        &root,
                        vec![
                            input("repo.registered", &format!("repo_{worker}_{batch}_a")),
                            input(
                                "workspace.file_written",
                                &format!("repo_{worker}_{batch}_b"),
                            ),
                        ],
                    )
                    .unwrap();
                }
            });
        }
    });

    let listed = list_audit_events(
        dir.path(),
        AuditQuery {
            actor_id: None,
            tenant_id: None,
            repo_id: None,
            event_type: None,
            limit: Some(500),
        },
    )
    .unwrap();

    assert_eq!(listed.len(), 500);
}

fn input(event_type: &str, repo_id: &str) -> AuditEventInput {
    AuditEventInput {
        event_type: event_type.to_string(),
        actor_id: Some("actor_test".to_string()),
        tenant_id: Some("tenant_test".to_string()),
        repo_id: Some(repo_id.to_string()),
        node_id: Some("node_local".to_string()),
        workspace_id: None,
        operation: None,
        status: Some("ok".to_string()),
        request_id: None,
        requested_scope: None,
        effective_scope: None,
        data: serde_json::json!({}),
    }
}
