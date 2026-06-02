use crate::error::StoreError;
use crate::ids::{capability_id, repository_id};
use crate::log::{append_record, ensure_log, replay_latest};
use crate::types::*;
use chrono::Utc;
use serde::{de::DeserializeOwned, Serialize};
use std::path::{Path, PathBuf};

pub const DATA_DIRS: &[&str] = &[
    "catalog",
    "repos",
    "repos/bare",
    "workspaces",
    "workspaces/active",
    "leases",
    "audit",
    "graph",
    "search",
    "snapshots",
    "federation",
    "federation/mirrors",
    "federation/migrations",
    "tmp",
    "recovery",
    "config",
];

pub fn init_data_dir(data_dir: &Path, options: InitOptions) -> Result<InitReport, StoreError> {
    for dir in DATA_DIRS {
        std::fs::create_dir_all(data_dir.join(dir))?;
    }
    ensure_all_logs(data_dir)?;
    let manifest_path = data_dir.join("catalog/manifest.tdb");
    if !manifest_path.exists() {
        let manifest = serde_json::json!({
            "schemaVersion": 1,
            "createdBy": "treedb",
            "nodeId": options.node_id,
            "createdAt": Utc::now(),
            "directories": DATA_DIRS,
        });
        append_record(&manifest_path, "manifest", "manifest", &manifest)?;
    }
    Ok(InitReport {
        data_dir: data_dir.display().to_string(),
        directories: DATA_DIRS.iter().map(|entry| entry.to_string()).collect(),
        manifest_path: manifest_path.display().to_string(),
    })
}

pub fn seed_dev_records(
    data_dir: &Path,
    node_id: &str,
    base_url: &str,
) -> Result<SeedReport, StoreError> {
    let now = Utc::now();
    seed_volume_and_node(data_dir, node_id, base_url, now)?;
    put_record(
        data_dir,
        "catalog/tenants.tdb",
        "tenant",
        "tenant_demo",
        &TenantRecord {
            id: "tenant_demo".to_string(),
            source: "dev".to_string(),
            updated_at: now,
        },
    )?;
    put_record(
        data_dir,
        "catalog/actors.tdb",
        "actor",
        "actor_demo",
        &ActorRecord {
            id: "actor_demo".to_string(),
            tenant_ids: vec!["tenant_demo".to_string()],
            updated_at: now,
        },
    )?;
    let capabilities = vec![
        "repos:read",
        "repos:write",
        "remotes:read",
        "remotes:write",
        "files:read",
        "files:write",
        "files:delete",
        "files:search",
        "graph:refresh",
        "graph:query",
        "workspace:create",
        "workspace:exec:read_only",
        "workspace:exec:verification",
        "workspace:exec:write_limited",
        "git:read",
        "git:diff",
        "git:commit",
        "git:fetch",
        "git:push",
        "snapshot:build",
        "artifact:export",
        "registry:read",
        "registry:write",
        "mirror:read",
        "mirror:write",
        "migration:read",
        "migration:write",
        "query:federated",
        "policy:read",
        "policy:write",
        "audit:read",
    ]
    .into_iter()
    .map(String::from)
    .collect::<Vec<_>>();
    let refs = vec!["refs/heads/*".to_string()];
    let paths = vec!["**".to_string()];
    let cap_id = capability_id("actor_demo", "tenant_demo", &capabilities, &refs, &paths);
    put_record(
        data_dir,
        "catalog/capability_grants.tdb",
        "capability_grant",
        &cap_id,
        &CapabilityGrantRecord {
            id: cap_id.clone(),
            actor_id: "actor_demo".to_string(),
            tenant_id: "tenant_demo".to_string(),
            repo_ids: vec!["*".to_string()],
            capabilities,
            refs,
            paths,
            expires_at: None,
        },
    )?;
    Ok(SeedReport {
        node_id: node_id.to_string(),
        tenant_id: "tenant_demo".to_string(),
        actor_id: "actor_demo".to_string(),
    })
}

pub fn seed_local_records(
    data_dir: &Path,
    node_id: &str,
    base_url: &str,
) -> Result<SeedReport, StoreError> {
    seed_volume_and_node(data_dir, node_id, base_url, Utc::now())?;
    Ok(SeedReport {
        node_id: node_id.to_string(),
        tenant_id: String::new(),
        actor_id: String::new(),
    })
}

fn seed_volume_and_node(
    data_dir: &Path,
    node_id: &str,
    base_url: &str,
    now: chrono::DateTime<Utc>,
) -> Result<(), StoreError> {
    put_record(
        data_dir,
        "catalog/volumes.tdb",
        "volume",
        "volume_local",
        &VolumeRecord {
            id: "volume_local".to_string(),
            root_path: data_dir.display().to_string(),
            capacity_policy: "local_dev".to_string(),
            repository_count: 0,
            status: "active".to_string(),
        },
    )?;
    put_record(
        data_dir,
        "catalog/nodes.tdb",
        "node",
        node_id,
        &NodeRecord {
            id: node_id.to_string(),
            base_url: base_url.to_string(),
            role: "primary".to_string(),
            capacity: serde_json::json!({"mode": "local"}),
            health: "healthy".to_string(),
            last_seen_at: now,
        },
    )?;
    Ok(())
}

pub fn put_repository(
    data_dir: &Path,
    input: RepositoryInput,
) -> Result<RepositoryRecord, StoreError> {
    if input.name.trim().is_empty() {
        return Err(StoreError::Validation(
            "repository name is required".to_string(),
        ));
    }
    if input.local_path.trim().is_empty() {
        return Err(StoreError::Validation("local path is required".to_string()));
    }
    let now = Utc::now();
    let id = repository_id(&input.name, &input.local_path, input.remote_url.as_deref());
    let existing = get_repository(data_dir, &id)?;
    let created_at = existing
        .as_ref()
        .map(|record| record.created_at)
        .unwrap_or(now);
    let record = RepositoryRecord {
        id: id.clone(),
        name: input.name,
        storage_kind: "local_path".to_string(),
        local_path: input.local_path,
        default_ref: input
            .default_ref
            .unwrap_or_else(|| "refs/heads/main".to_string()),
        status: "registered".to_string(),
        remote_url: input.remote_url,
        created_at,
        updated_at: now,
    };
    put_record(
        data_dir,
        "catalog/repositories.tdb",
        "repository",
        &id,
        &record,
    )?;
    Ok(record)
}

pub fn list_repositories(data_dir: &Path) -> Result<Vec<RepositoryRecord>, StoreError> {
    list_records(data_dir, "catalog/repositories.tdb", "repository")
}

pub fn get_repository(
    data_dir: &Path,
    repo_id: &str,
) -> Result<Option<RepositoryRecord>, StoreError> {
    get_record(data_dir, "catalog/repositories.tdb", "repository", repo_id)
}

pub fn list_nodes(data_dir: &Path) -> Result<Vec<NodeRecord>, StoreError> {
    list_records(data_dir, "catalog/nodes.tdb", "node")
}

pub fn get_node(data_dir: &Path, node_id: &str) -> Result<Option<NodeRecord>, StoreError> {
    get_record(data_dir, "catalog/nodes.tdb", "node", node_id)
}

pub(crate) fn put_record<T: Serialize>(
    data_dir: &Path,
    relative_path: &str,
    kind: &str,
    record_id: &str,
    record: &T,
) -> Result<(), StoreError> {
    append_record(&data_dir.join(relative_path), kind, record_id, record)
}

pub(crate) fn list_records<T: DeserializeOwned + Serialize + Clone>(
    data_dir: &Path,
    relative_path: &str,
    kind: &str,
) -> Result<Vec<T>, StoreError> {
    Ok(replay_latest(&data_dir.join(relative_path), kind)?
        .into_values()
        .collect())
}

pub(crate) fn get_record<T: DeserializeOwned + Serialize + Clone>(
    data_dir: &Path,
    relative_path: &str,
    kind: &str,
    record_id: &str,
) -> Result<Option<T>, StoreError> {
    Ok(replay_latest(&data_dir.join(relative_path), kind)?.remove(record_id))
}

fn ensure_all_logs(data_dir: &Path) -> Result<(), StoreError> {
    for (path, kind) in log_files() {
        ensure_log(&data_dir.join(path), kind)?;
    }
    Ok(())
}

fn log_files() -> Vec<(PathBuf, &'static str)> {
    vec![
        ("catalog/repositories.tdb".into(), "repository"),
        ("catalog/repository_remotes.tdb".into(), "repository_remote"),
        ("catalog/repository_refs.tdb".into(), "repository_ref"),
        ("catalog/volumes.tdb".into(), "volume"),
        ("catalog/nodes.tdb".into(), "node"),
        ("catalog/tenants.tdb".into(), "tenant"),
        ("catalog/actors.tdb".into(), "actor"),
        ("catalog/capability_grants.tdb".into(), "capability_grant"),
        ("catalog/repo_access.tdb".into(), "repo_access"),
        ("catalog/connected_tokens.tdb".into(), "connected_token"),
        ("catalog/policy_refreshes.tdb".into(), "policy_refresh"),
        (
            "federation/repository_placements.tdb".into(),
            "repository_placement",
        ),
        ("federation/mirrors.tdb".into(), "mirror"),
        ("federation/mirror_syncs.tdb".into(), "mirror_sync"),
        ("federation/migrations.tdb".into(), "migration"),
        ("audit/events.tdb".into(), "audit_event"),
        ("snapshots/snapshots.tdb".into(), "snapshot"),
        ("snapshots/artifacts.tdb".into(), "artifact"),
        ("config/dev_tokens.tdb".into(), "dev_token"),
        ("workspaces/sessions.tdb".into(), "workspace"),
        ("workspaces/files.tdb".into(), "workspace_file"),
        ("leases/leases.tdb".into(), "lease"),
    ]
}
