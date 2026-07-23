use super::*;

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
