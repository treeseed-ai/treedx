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
    #[serde(default)]
    pub repository_name: Option<String>,
    #[serde(default)]
    pub local_path: Option<String>,
    #[serde(default)]
    pub storage_relative_path: Option<String>,
    pub default_ref: Option<String>,
    pub remote_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryRecord {
    pub id: String,
    #[serde(default)]
    pub repository_name: String,
    pub name: String,
    pub storage_kind: String,
    #[serde(default)]
    pub storage_relative_path: String,
    #[serde(default)]
    pub local_path: String,
    pub default_ref: String,
    pub status: String,
    pub remote_url: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryNameRecord {
    pub repository_name: String,
    pub repository_id: String,
    pub created_at: DateTime<Utc>,
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
pub struct FederationPeerRecord {
    pub id: String,
    pub base_url: String,
    pub relationship: String,
    pub trust_states: Vec<String>,
    pub discovered_via_node_id: Option<String>,
    pub parent_node_ids: Vec<String>,
    pub public_key_pem: String,
    pub accepted_issuer_ids: Vec<String>,
    pub allowed_capabilities: Vec<String>,
    pub can_advertise_repos: bool,
    pub can_receive_queries: bool,
    pub can_receive_write_proxy: bool,
    pub can_mirror_repos: bool,
    pub promotion_eligible: bool,
    pub health: String,
    pub last_seen_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
    pub blocked_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryAdvertisementRecord {
    pub repository_id: String,
    pub repository_name: String,
    pub owner_node_id: String,
    pub advertised_by_node_id: String,
    pub default_ref: String,
    pub refs: Vec<String>,
    pub paths: Vec<String>,
    pub capabilities: Vec<String>,
    pub visibility: String,
    pub graph_available: bool,
    pub snapshots_available: bool,
    pub mirror_eligible: bool,
    pub catalog_version: u64,
    pub last_seen_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FederationRouteRecord {
    pub repository_id: String,
    pub repository_name: String,
    pub primary_node_id: String,
    pub mirror_node_ids: Vec<String>,
    pub read_policy: String,
    pub write_policy: String,
    pub owner_node_id: String,
    pub source: String,
    pub confidence: String,
    pub freshness: serde_json::Value,
    pub catalog_version: u64,
    pub last_seen_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NodeCapacityRecord {
    pub node_id: String,
    pub storage_total_bytes: u64,
    pub storage_available_bytes: u64,
    pub repository_count: u64,
    pub active_workspace_count: u64,
    pub cpu_load: Option<f64>,
    pub memory_pressure: Option<f64>,
    pub graph_queue_depth: Option<u64>,
    pub audit_queue_depth: Option<u64>,
    pub accepted_repo_classes: Vec<String>,
    pub regions: Vec<String>,
    pub health: String,
    pub sampled_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MirrorAssignmentRecord {
    pub id: String,
    pub repository_id: String,
    pub source_node_id: String,
    pub target_node_id: String,
    pub mode: String,
    pub promotion_eligible: bool,
    pub freshness_requirement: serde_json::Value,
    pub status: String,
    pub last_synced_commit: Option<String>,
    pub last_sync_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceRouteRecord {
    pub workspace_id: String,
    pub repository_id: String,
    pub node_id: String,
    pub actor_id: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub expires_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IdempotencyRecord {
    pub id: String,
    pub method: String,
    pub path: String,
    pub body_hash: String,
    pub status: String,
    pub response_json: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
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
    pub plan: bool,
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
    #[serde(default)]
    pub expires_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub revoked_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub revoked_by_actor_id: Option<String>,
    #[serde(default)]
    pub revocation_reason: Option<String>,
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
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub expires_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub policy_version: Option<String>,
    #[serde(default)]
    pub policy_hash: Option<String>,
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
    #[serde(default)]
    pub policy_version: Option<String>,
    #[serde(default)]
    pub policy_hash: Option<String>,
    #[serde(default)]
    pub revoked_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub revoked_reason: Option<String>,
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
    #[serde(default)]
    pub expected_content_hash: Option<String>,
    pub base_sha: Option<String>,
    #[serde(default)]
    pub content_type: Option<String>,
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
    #[serde(default)]
    pub expected_content_hash: Option<String>,
    pub base_sha: Option<String>,
    #[serde(default)]
    pub content_type: Option<String>,
    pub size: u64,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceCommitMarkInput {
    pub workspace_id: String,
    pub commit_sha: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceQuarantineInput {
    pub workspace_id: String,
    pub policy_version: Option<String>,
    pub policy_hash: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspacePolicyUpdateInput {
    pub workspace_id: String,
    pub policy_version: String,
    pub policy_hash: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageCompactInput {
    #[serde(default)]
    pub logs: Vec<String>,
    #[serde(default)]
    pub plan: bool,
    #[serde(default = "default_backup_before")]
    pub backup_before: bool,
}

fn default_backup_before() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageCompactFileResult {
    pub file: String,
    pub records_before: u64,
    pub records_after: u64,
    pub bytes_before: u64,
    pub bytes_after: u64,
    pub compacted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageCompactResult {
    pub status: String,
    pub plan: bool,
    pub backup_id: Option<String>,
    pub files: Vec<StorageCompactFileResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageBackupInput {
    #[serde(default)]
    pub include: Vec<String>,
    #[serde(default = "default_verify_backup")]
    pub verify: bool,
}

fn default_verify_backup() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageBackupResult {
    pub backup_id: String,
    pub format: String,
    pub uri: String,
    pub checksum: String,
    pub byte_length: u64,
    pub verified: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphRefreshJobRecord {
    pub job_id: String,
    pub repo_id: String,
    pub ref_name: String,
    #[serde(default)]
    pub requested_paths: Vec<String>,
    #[serde(default)]
    pub changed_paths: Vec<String>,
    #[serde(default)]
    pub base_graph_version: Option<String>,
    #[serde(default)]
    pub graph_version: Option<String>,
    pub refresh_mode: String,
    #[serde(default)]
    pub fallback_reason: Option<String>,
    #[serde(default)]
    pub stale: bool,
    pub status: String,
    pub started_at: DateTime<Utc>,
    #[serde(default)]
    pub completed_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub indexed_path_count: u64,
    #[serde(default)]
    pub removed_path_count: u64,
    #[serde(default)]
    pub error_code: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexManifestRecord {
    pub index_version: String,
    pub repo_id: String,
    pub ref_name: String,
    #[serde(default)]
    pub graph_version: Option<String>,
    #[serde(default)]
    pub segment_ids: Vec<String>,
    #[serde(default)]
    pub indexed_paths: Vec<String>,
    #[serde(default)]
    pub source_commit: Option<String>,
    #[serde(default)]
    pub stale: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexSegmentRecord {
    pub segment_id: String,
    pub repo_id: String,
    pub ref_name: String,
    pub path_count: u64,
    pub document_count: u64,
    pub content_hash: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexCompactInput {
    pub repo_id: String,
    pub ref_name: String,
    #[serde(default)]
    pub plan: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchIndexCompactResult {
    pub repo_id: String,
    pub ref_name: String,
    pub plan: bool,
    pub segments_before: u64,
    pub segments_after: u64,
    pub compacted: bool,
}
