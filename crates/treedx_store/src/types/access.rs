use super::*;

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
