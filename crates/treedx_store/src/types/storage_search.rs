use super::*;

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
