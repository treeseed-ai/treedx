use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepositoryInspection {
    pub path: String,
    pub exists: bool,
    pub is_git_repository: bool,
    pub is_bare: Option<bool>,
    pub head: Option<String>,
    pub refs: Vec<GitRefSummary>,
    pub remotes: Vec<GitRemoteSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitRefSummary {
    pub name: String,
    pub target: Option<String>,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitRemoteSummary {
    pub name: String,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedRef {
    pub name: String,
    pub target: String,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TreeEntrySummary {
    pub path: String,
    pub name: String,
    pub object_id: String,
    pub kind: String,
    pub mode: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BlobRead {
    pub path: String,
    pub object_id: String,
    pub byte_length: usize,
    pub content_base64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecursiveTreeEntry {
    pub path: String,
    pub object_id: String,
    pub kind: String,
    pub mode: String,
    pub size: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileChange {
    pub path: String,
    pub op: String,
    pub content_base64: Option<String>,
    pub expected_sha: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitOverlayInput {
    pub repo_path: String,
    pub base_commit_sha: String,
    pub branch_name: String,
    pub message: String,
    pub author_name: String,
    pub author_email: String,
    pub changes: Vec<FileChange>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommitOverlayResult {
    pub commit_sha: String,
    pub branch_name: String,
    pub changed_paths: Vec<String>,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ChangedPath {
    pub path: String,
    pub status: String,
    pub base_object_id: Option<String>,
    pub object_id: Option<String>,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchRemoteInput {
    pub repo_path: String,
    pub remote_url: Option<String>,
    pub remote_name: Option<String>,
    pub refspecs: Vec<String>,
    pub plan: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchRemoteResult {
    pub remote_name: String,
    pub remote_url: Option<String>,
    pub refspecs: Vec<String>,
    pub updated_refs: Vec<String>,
    pub received_pack: bool,
    pub before_head: Option<String>,
    pub after_head: Option<String>,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushRemoteInput {
    pub repo_path: String,
    pub remote_url: Option<String>,
    pub remote_name: Option<String>,
    pub refspecs: Vec<String>,
    pub plan: bool,
    #[serde(default)]
    pub expected_remote_head: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PushRemoteResult {
    pub remote_name: String,
    pub remote_url: Option<String>,
    pub refspecs: Vec<String>,
    pub updated_refs: Vec<String>,
    pub rejected_refs: Vec<String>,
    pub before_head: Option<String>,
    pub after_head: Option<String>,
    pub status: String,
    pub backend: String,
}
