use base64::Engine;
use chrono::{Duration, Utc};
use tempfile::tempdir;
use treedb_store::*;

#[test]
fn init_data_dir_creates_directories_and_manifest() {
    let dir = tempdir().unwrap();
    let report = init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    assert!(dir.path().join("catalog/manifest.tdb").exists());
    assert!(dir.path().join("repos/bare").is_dir());
    assert!(report
        .directories
        .contains(&"workspaces/active".to_string()));
}

#[test]
fn seed_dev_records_is_idempotent() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    seed_dev_records(dir.path(), "node_local", "http://localhost:4000").unwrap();
    seed_dev_records(dir.path(), "node_local", "http://localhost:4000").unwrap();
    assert_eq!(list_nodes(dir.path()).unwrap().len(), 1);
    let scope = resolve_effective_scope(dir.path(), "actor_demo", None).unwrap();
    assert!(scope.capabilities.contains(&"repos:write".to_string()));
}

#[test]
fn repository_records_persist_and_ids_are_deterministic() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    let input = RepositoryInput {
        name: "demo".to_string(),
        local_path: "/var/lib/treedb/repos/bare/demo.git".to_string(),
        default_ref: None,
        remote_url: Some("https://example.invalid/demo.git".to_string()),
    };
    let first = put_repository(dir.path(), input.clone()).unwrap();
    let second = put_repository(dir.path(), input).unwrap();
    assert_eq!(first.id, second.id);
    assert_eq!(list_repositories(dir.path()).unwrap().len(), 1);
    assert_eq!(
        get_repository(dir.path(), &first.id).unwrap().unwrap().name,
        "demo"
    );
}

#[test]
fn placement_and_mirrors_persist() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    put_repository_placement(
        dir.path(),
        RepositoryPlacementRecord {
            repository_id: "repo_demo".to_string(),
            primary_node_id: "node_local".to_string(),
            mirror_node_ids: vec![],
            read_policy: "primary_or_mirror".to_string(),
            write_policy: "primary_only".to_string(),
            migration_state: "stable".to_string(),
        },
    )
    .unwrap();
    assert!(get_repository_placement(dir.path(), "repo_demo")
        .unwrap()
        .is_some());
    put_mirror(
        dir.path(),
        MirrorRecord {
            id: String::new(),
            repository_id: "repo_demo".to_string(),
            source_node_id: "node_local".to_string(),
            target_node_id: "node_b".to_string(),
            mode: "read_replica".to_string(),
            last_seen_commit: None,
            behind_by: None,
            status: "planned".to_string(),
        },
    )
    .unwrap();
    assert_eq!(list_mirrors(dir.path(), "repo_demo").unwrap().len(), 1);
}

#[test]
fn dev_token_records_persist() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    let token_hash = hash_token("secret");
    put_dev_token(
        dir.path(),
        DevTokenRecord {
            token_hash: token_hash.clone(),
            actor_id: "actor_demo".to_string(),
            tenant_id: "tenant_demo".to_string(),
            expires_at: Utc::now() + Duration::seconds(60),
            created_at: Utc::now(),
        },
    )
    .unwrap();
    assert_eq!(
        get_dev_token_by_hash(dir.path(), &token_hash)
            .unwrap()
            .unwrap()
            .actor_id,
        "actor_demo"
    );
}

#[test]
fn workspaces_persist_and_writable_lease_conflicts() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    let input = workspace_input("ws_one", "refs/heads/agent/demo", 60);
    let first = put_workspace(dir.path(), input.clone()).unwrap();
    assert_eq!(first.status, "ready");
    assert!(first.lease_id.is_some());
    assert!(get_workspace(dir.path(), "ws_one").unwrap().is_some());

    let mut duplicate = input;
    duplicate.id = Some("ws_two".to_string());
    let error = put_workspace(dir.path(), duplicate).unwrap_err();
    assert_eq!(error.code(), "conflict");

    let closed = close_workspace(dir.path(), "ws_one").unwrap().unwrap();
    assert_eq!(closed.status, "closed");

    let mut after_close = workspace_input("ws_three", "refs/heads/agent/demo", 60);
    after_close.materialized_path = "/tmp/ws_three".to_string();
    assert!(put_workspace(dir.path(), after_close).is_ok());
}

#[test]
fn expired_workspace_cleanup_marks_workspace_and_releases_lease() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    put_workspace(
        dir.path(),
        workspace_input("ws_expired", "refs/heads/agent/expired", 1),
    )
    .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(1200));
    let report = cleanup_expired_workspaces(dir.path()).unwrap();
    assert_eq!(report.expired_workspace_ids, vec!["ws_expired".to_string()]);
    assert_eq!(
        get_workspace(dir.path(), "ws_expired")
            .unwrap()
            .unwrap()
            .status,
        "expired"
    );
}

fn workspace_input(id: &str, branch_name: &str, ttl_seconds: i64) -> WorkspaceInput {
    WorkspaceInput {
        id: Some(id.to_string()),
        repository_id: "repo_demo".to_string(),
        node_id: "node_local".to_string(),
        actor_id: "actor_demo".to_string(),
        tenant_id: "tenant_demo".to_string(),
        base_ref: "refs/heads/main".to_string(),
        base_commit_sha: "1111111111111111111111111111111111111111".to_string(),
        branch_name: Some(branch_name.to_string()),
        mode: "writable".to_string(),
        allowed_paths: vec!["docs/**".to_string()],
        capabilities: vec!["files:read".to_string(), "files:write".to_string()],
        ttl_seconds,
        materialized_path: format!("/tmp/{id}"),
        effective_scope: EffectiveScope {
            actor_id: "actor_demo".to_string(),
            tenant_id: "tenant_demo".to_string(),
            repo_ids: vec!["repo_demo".to_string()],
            capabilities: vec!["files:read".to_string(), "files:write".to_string()],
            refs: vec![branch_name.to_string()],
            paths: vec!["docs/**".to_string()],
            source: Some("test".to_string()),
            expires_at: None,
        },
    }
}

#[test]
fn workspace_file_overlay_records_persist_and_latest_wins() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    put_workspace(
        dir.path(),
        workspace_input("ws_files", "refs/heads/agent/files", 60),
    )
    .unwrap();

    let first = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_files".to_string(),
            path: "docs/readme.md".to_string(),
            op: "put".to_string(),
            encoding: Some("utf8".to_string()),
            content_base64: Some(base64::engine::general_purpose::STANDARD.encode("one")),
            expected_sha: None,
            base_sha: None,
        },
    )
    .unwrap();
    let second = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_files".to_string(),
            path: "docs/readme.md".to_string(),
            op: "put".to_string(),
            encoding: Some("utf8".to_string()),
            content_base64: Some(base64::engine::general_purpose::STANDARD.encode("two")),
            expected_sha: Some(first.content_hash.unwrap()),
            base_sha: None,
        },
    )
    .unwrap();

    assert_eq!(first.id, second.id);
    assert_eq!(
        get_workspace_file(dir.path(), "ws_files", "docs/readme.md")
            .unwrap()
            .unwrap()
            .content_hash,
        second.content_hash
    );
    assert_eq!(
        read_workspace_file_content(dir.path(), &second)
            .unwrap()
            .unwrap(),
        b"two"
    );
    assert_eq!(
        list_workspace_files(dir.path(), "ws_files").unwrap().len(),
        1
    );

    let deleted = put_workspace_file(
        dir.path(),
        WorkspaceFileInput {
            workspace_id: "ws_files".to_string(),
            path: "docs/readme.md".to_string(),
            op: "delete".to_string(),
            encoding: None,
            content_base64: None,
            expected_sha: second.content_hash,
            base_sha: None,
        },
    )
    .unwrap();
    assert_eq!(deleted.op, "delete");
    assert!(deleted.content_hash.is_none());
}

#[test]
fn mark_workspace_committed_sets_status_and_releases_lease() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    let workspace = put_workspace(
        dir.path(),
        workspace_input("ws_commit", "refs/heads/agent/commit", 60),
    )
    .unwrap();
    let lease_id = workspace.lease_id.unwrap();
    let committed = mark_workspace_committed(
        dir.path(),
        WorkspaceCommitMarkInput {
            workspace_id: "ws_commit".to_string(),
            commit_sha: "2222222222222222222222222222222222222222".to_string(),
        },
    )
    .unwrap();
    assert_eq!(committed.status, "committed");
    assert_eq!(
        committed.commit_sha.as_deref(),
        Some("2222222222222222222222222222222222222222")
    );
    assert_eq!(
        treedb_store::workspace::get_lease(dir.path(), &lease_id)
            .unwrap()
            .unwrap()
            .status,
        "released"
    );
}
