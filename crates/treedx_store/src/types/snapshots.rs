use super::*;

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
