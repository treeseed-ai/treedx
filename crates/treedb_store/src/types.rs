use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitOptions {
    pub node_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitReport {
    pub data_dir: String,
    pub directories: Vec<String>,
    pub manifest_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SeedReport {
    pub node_id: String,
    pub tenant_id: String,
    pub actor_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryInput {
    pub name: String,
    pub local_path: String,
    pub default_ref: Option<String>,
    pub remote_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryRecord {
    pub id: String,
    pub name: String,
    pub storage_kind: String,
    pub local_path: String,
    pub default_ref: String,
    pub status: String,
    pub remote_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryRemoteRecord {
    pub repository_id: String,
    pub name: String,
    pub url: String,
    pub fetch_refspecs: Vec<String>,
    pub push_refspecs: Vec<String>,
    pub last_sync_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryRefRecord {
    pub repository_id: String,
    pub name: String,
    pub sha: String,
    pub kind: String,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VolumeRecord {
    pub id: String,
    pub root_path: String,
    pub capacity_policy: String,
    pub repository_count: u64,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NodeRecord {
    pub id: String,
    pub base_url: String,
    pub role: String,
    pub capacity: serde_json::Value,
    pub health: String,
    pub last_seen_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryPlacementRecord {
    pub repository_id: String,
    pub primary_node_id: String,
    pub mirror_node_ids: Vec<String>,
    pub read_policy: String,
    pub write_policy: String,
    pub migration_state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MirrorRecord {
    pub id: String,
    pub repository_id: String,
    pub source_node_id: String,
    pub target_node_id: String,
    pub mode: String,
    pub last_seen_commit: Option<String>,
    pub behind_by: Option<u64>,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TenantRecord {
    pub id: String,
    pub source: String,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActorRecord {
    pub id: String,
    pub tenant_ids: Vec<String>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilityGrantRecord {
    pub id: String,
    pub actor_id: String,
    pub tenant_id: String,
    pub repo_ids: Vec<String>,
    pub capabilities: Vec<String>,
    pub refs: Vec<String>,
    pub paths: Vec<String>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepoAccessRecord {
    pub repo_id: String,
    pub tenant_id: String,
    pub actor_ids: Vec<String>,
    pub capability_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DevTokenRecord {
    pub token_hash: String,
    pub actor_id: String,
    pub tenant_id: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EffectiveScope {
    pub actor_id: String,
    pub tenant_id: String,
    pub repo_ids: Vec<String>,
    pub capabilities: Vec<String>,
    pub refs: Vec<String>,
    pub paths: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEventInput {
    pub event_type: String,
    pub actor_id: Option<String>,
    pub tenant_id: Option<String>,
    pub repo_id: Option<String>,
    pub node_id: Option<String>,
    pub request_id: Option<String>,
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEventRecord {
    pub id: String,
    pub event_type: String,
    pub actor_id: Option<String>,
    pub tenant_id: Option<String>,
    pub repo_id: Option<String>,
    pub node_id: Option<String>,
    pub request_id: Option<String>,
    pub data: serde_json::Value,
    pub recorded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceInput {
    pub id: Option<String>,
    pub repository_id: String,
    pub node_id: String,
    pub actor_id: String,
    pub tenant_id: String,
    pub base_ref: String,
    pub branch_name: Option<String>,
    pub mode: String,
    pub allowed_paths: Vec<String>,
    pub capabilities: Vec<String>,
    pub ttl_seconds: i64,
    pub materialized_path: String,
    pub effective_scope: EffectiveScope,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRecord {
    pub id: String,
    pub repository_id: String,
    pub node_id: String,
    pub actor_id: String,
    pub tenant_id: String,
    pub base_ref: String,
    pub branch_name: Option<String>,
    pub mode: String,
    pub allowed_paths: Vec<String>,
    pub capabilities: Vec<String>,
    pub status: String,
    pub materialized_path: String,
    pub effective_scope: EffectiveScope,
    pub lease_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaseRecord {
    pub id: String,
    pub repository_id: String,
    pub branch_name: String,
    pub workspace_id: String,
    pub actor_id: String,
    pub mode: String,
    pub status: String,
    pub acquired_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub released_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupReport {
    pub expired_workspace_ids: Vec<String>,
    pub released_lease_ids: Vec<String>,
}
