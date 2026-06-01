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
