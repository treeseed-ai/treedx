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
pub struct SnapshotFileRecord {
    pub path: String,
    pub object_id: String,
    pub size: u64,
    pub content_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotManifestRecord {
    pub snapshot_id: String,
    pub repo_id: String,
    pub ref_name: String,
    pub commit_sha: String,
    pub kind: String,
    pub included_paths: Vec<String>,
    pub graph_version: Option<String>,
    pub file_count: u64,
    pub total_bytes: u64,
    pub files: Vec<SnapshotFileRecord>,
    pub checksums: serde_json::Value,
    pub artifact: Option<ArtifactRecord>,
    pub created_by_actor_id: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ArtifactRecord {
    pub artifact_id: String,
    pub snapshot_id: String,
    pub repo_id: String,
    pub format: String,
    pub size: u64,
    pub checksum: String,
    pub uri: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotBuildInput {
    pub snapshot_id: Option<String>,
    pub repo_id: String,
    pub ref_name: String,
    pub commit_sha: String,
    pub kind: String,
    pub included_paths: Vec<String>,
    pub graph_version: Option<String>,
    pub files: Vec<SnapshotArtifactFileInput>,
    pub created_by_actor_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SnapshotArtifactFileInput {
    pub path: String,
    pub object_id: String,
    pub content_base64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MirrorSyncRecord {
    pub id: String,
    pub mirror_id: String,
    pub repository_id: String,
    pub source_node_id: String,
    pub target_node_id: String,
    pub remote_url: Option<String>,
    pub remote_name: String,
    pub refspecs: Vec<String>,
    pub before_commit: Option<String>,
    pub after_commit: Option<String>,
    pub updated_refs: Vec<String>,
    pub received_pack: bool,
    pub behind_by: Option<u64>,
    pub status: String,
    pub error: Option<String>,
    pub started_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MigrationRecord {
    pub id: String,
    pub repository_id: String,
    pub source_node_id: String,
    pub target_node_id: String,
    pub mode: String,
    pub status: String,
    pub dry_run: bool,
    pub require_mirror_synced: bool,
    pub previous_placement: Option<RepositoryPlacementRecord>,
    pub resulting_placement: Option<RepositoryPlacementRecord>,
    pub validation: serde_json::Value,
    pub created_by_actor_id: Option<String>,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
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
    pub source: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditEventInput {
    pub event_type: String,
    pub actor_id: Option<String>,
    pub tenant_id: Option<String>,
    pub repo_id: Option<String>,
    pub node_id: Option<String>,
    pub workspace_id: Option<String>,
    pub operation: Option<String>,
    pub status: Option<String>,
    pub request_id: Option<String>,
    pub requested_scope: Option<serde_json::Value>,
    pub effective_scope: Option<serde_json::Value>,
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
    pub workspace_id: Option<String>,
    pub operation: Option<String>,
    pub status: Option<String>,
    pub request_id: Option<String>,
    pub requested_scope: Option<serde_json::Value>,
    pub effective_scope: Option<serde_json::Value>,
    pub data: serde_json::Value,
    pub recorded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectedTokenRecord {
    pub jti: String,
    pub actor_id: String,
    pub tenant_id: String,
    pub issuer: String,
    pub audience: String,
    pub subject: String,
    pub expires_at: DateTime<Utc>,
    pub seen_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PolicyRefreshRecord {
    pub id: String,
    pub source: String,
    pub actor_id: Option<String>,
    pub tenant_id: Option<String>,
    pub status: String,
    pub data: serde_json::Value,
    pub refreshed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuditQuery {
    pub actor_id: Option<String>,
    pub tenant_id: Option<String>,
    pub repo_id: Option<String>,
    pub event_type: Option<String>,
    pub limit: Option<u32>,
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
    #[serde(default)]
    pub base_commit_sha: String,
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
    pub base_commit_sha: String,
    pub branch_name: Option<String>,
    pub mode: String,
    pub allowed_paths: Vec<String>,
    pub capabilities: Vec<String>,
    pub status: String,
    pub materialized_path: String,
    pub effective_scope: EffectiveScope,
    pub lease_id: Option<String>,
    pub commit_sha: Option<String>,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceFileInput {
    pub workspace_id: String,
    pub path: String,
    pub op: String,
    pub encoding: Option<String>,
    pub content_base64: Option<String>,
    pub expected_sha: Option<String>,
    pub base_sha: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceFileRecord {
    pub id: String,
    pub workspace_id: String,
    pub path: String,
    pub op: String,
    pub encoding: Option<String>,
    pub content_hash: Option<String>,
    pub content_path: Option<String>,
    pub expected_sha: Option<String>,
    pub base_sha: Option<String>,
    pub size: u64,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceCommitMarkInput {
    pub workspace_id: String,
    pub commit_sha: String,
}
