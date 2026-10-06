use super::*;

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
