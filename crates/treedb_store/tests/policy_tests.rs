use chrono::{Duration, Utc};
use tempfile::tempdir;
use treedb_store::*;

#[test]
fn effective_scope_resolves_wildcard_dev_capabilities() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".to_string(),
        },
    )
    .unwrap();
    seed_dev_records(dir.path(), "node_local", "http://localhost:4000").unwrap();
    let scope = resolve_effective_scope(dir.path(), "actor_demo", Some("repo_any")).unwrap();
    assert_eq!(scope.tenant_id, "tenant_demo");
    assert!(scope.repo_ids.contains(&"*".to_string()));
    assert!(scope.capabilities.contains(&"registry:write".to_string()));
    assert!(scope.capabilities.contains(&"files:delete".to_string()));
    assert!(scope.capabilities.contains(&"audit:read".to_string()));
}

#[test]
fn capability_grants_filter_and_expire() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    put_capability_grant(
        dir.path(),
        CapabilityGrantRecord {
            id: String::new(),
            actor_id: "actor_a".into(),
            tenant_id: "tenant_a".into(),
            repo_ids: vec!["repo_a".into()],
            capabilities: vec!["files:read".into()],
            refs: vec!["refs/heads/main".into()],
            paths: vec!["docs/**".into()],
            expires_at: None,
        },
    )
    .unwrap();
    put_capability_grant(
        dir.path(),
        CapabilityGrantRecord {
            id: "expired".into(),
            actor_id: "actor_a".into(),
            tenant_id: "tenant_a".into(),
            repo_ids: vec!["repo_b".into()],
            capabilities: vec!["files:write".into()],
            refs: vec!["*".into()],
            paths: vec!["**".into()],
            expires_at: Some(Utc::now() - Duration::seconds(1)),
        },
    )
    .unwrap();

    assert_eq!(
        list_capability_grants(dir.path(), Some("actor_a"), Some("repo_a"))
            .unwrap()
            .len(),
        1
    );
    let scope = resolve_effective_scope(dir.path(), "actor_a", Some("repo_a")).unwrap();
    assert!(scope.capabilities.contains(&"files:read".into()));
    assert!(!scope.capabilities.contains(&"files:write".into()));
    assert!(resolve_effective_scope(dir.path(), "actor_a", Some("repo_b")).is_err());
}

#[test]
fn connected_token_policy_refresh_and_audit_records_persist() {
    let dir = tempdir().unwrap();
    init_data_dir(
        dir.path(),
        InitOptions {
            node_id: "node_local".into(),
        },
    )
    .unwrap();
    let expires_at = Utc::now() + Duration::hours(1);
    put_connected_token(
        dir.path(),
        ConnectedTokenRecord {
            jti: "jwt_1".into(),
            actor_id: "actor_a".into(),
            tenant_id: "tenant_a".into(),
            issuer: "issuer".into(),
            audience: "aud".into(),
            subject: "sub".into(),
            expires_at,
            seen_at: Utc::now(),
        },
    )
    .unwrap();
    assert_eq!(
        get_connected_token(dir.path(), "jwt_1")
            .unwrap()
            .unwrap()
            .actor_id,
        "actor_a"
    );

    put_policy_refresh(
        dir.path(),
        PolicyRefreshRecord {
            id: "pol_1".into(),
            source: "connected".into(),
            actor_id: Some("actor_a".into()),
            tenant_id: Some("tenant_a".into()),
            status: "noop".into(),
            data: serde_json::json!({}),
            refreshed_at: Utc::now(),
        },
    )
    .unwrap();

    append_audit_event(
        dir.path(),
        AuditEventInput {
            event_type: "file.written".into(),
            actor_id: Some("actor_a".into()),
            tenant_id: Some("tenant_a".into()),
            repo_id: Some("repo_a".into()),
            node_id: Some("node_local".into()),
            workspace_id: Some("ws_1".into()),
            operation: Some("files.write".into()),
            status: Some("ok".into()),
            request_id: Some("req_1".into()),
            requested_scope: Some(serde_json::json!({"repoIds":["repo_a"]})),
            effective_scope: Some(serde_json::json!({"repoIds":["repo_a"]})),
            data: serde_json::json!({"path":"docs/a.md"}),
        },
    )
    .unwrap();

    let events = list_audit_events(
        dir.path(),
        AuditQuery {
            actor_id: Some("actor_a".into()),
            tenant_id: None,
            repo_id: Some("repo_a".into()),
            event_type: Some("file.written".into()),
            limit: Some(10),
        },
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].workspace_id.as_deref(), Some("ws_1"));
}
