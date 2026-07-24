use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphDocumentInput {
    pub path: String,
    pub object_id: String,
    pub size: u64,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphIndexInput {
    pub repo_id: String,
    pub ref_name: String,
    pub commit_sha: String,
    pub graph_version: Option<String>,
    #[serde(default)]
    pub documents: Vec<GraphDocumentInput>,
    pub previous_manifest: Option<GraphManifest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphIndex {
    pub manifest: GraphManifest,
    pub documents: Vec<GraphDocument>,
    pub nodes: Vec<GraphNode>,
    pub edges: Vec<GraphEdge>,
    pub metrics: GraphMetrics,
    pub diagnostics: GraphDiagnostics,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphManifest {
    pub schema_version: u32,
    pub graph_version: String,
    pub repo_id: String,
    pub ref_name: String,
    pub commit_sha: String,
    pub created_at: DateTime<Utc>,
    pub paths_hash: String,
    pub node_count: u64,
    pub edge_count: u64,
    pub document_count: u64,
    pub metrics: GraphMetrics,
    pub delta: GraphDelta,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GraphMetrics {
    pub total_files: u64,
    pub total_sections: u64,
    pub total_entities: u64,
    pub total_edges: u64,
    pub skipped_binary_or_invalid_utf8: u64,
    pub unresolved_references: u64,
    pub last_refresh_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GraphDelta {
    pub added: Vec<String>,
    pub modified: Vec<String>,
    pub removed: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GraphDiagnostics {
    pub warnings: Vec<String>,
    pub skipped_paths: Vec<String>,
    pub invalid_frontmatter_paths: Vec<String>,
    pub unresolved_links: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphDocument {
    pub path: String,
    pub object_id: String,
    pub size: u64,
    pub content_hash: String,
    pub title: String,
    pub body: String,
    pub frontmatter: serde_json::Value,
    pub section_ids: Vec<String>,
    pub link_targets: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphNode {
    pub id: String,
    pub node_type: String,
    pub entity_type: Option<String>,
    pub owner_file_id: Option<String>,
    pub path: Option<String>,
    pub slug: Option<String>,
    pub title: Option<String>,
    pub heading: Option<String>,
    pub heading_path: Option<String>,
    pub level: Option<u32>,
    pub text: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub series: Option<String>,
    pub file_id: Option<String>,
    pub status: Option<String>,
    pub canonical: Option<bool>,
    pub version: Option<String>,
    pub domain: Option<String>,
    #[serde(default)]
    pub audience: Vec<String>,
    pub updated_at: Option<String>,
    #[serde(default)]
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphEdge {
    pub id: String,
    #[serde(rename = "type")]
    pub edge_type: String,
    pub source_id: String,
    pub target_id: String,
    pub owner_file_id: Option<String>,
    #[serde(default)]
    pub data: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GraphQueryOptions {
    pub limit: Option<u32>,
    #[serde(default)]
    pub node_types: Vec<String>,
    #[serde(default)]
    pub edge_types: Vec<String>,
    pub direction: Option<String>,
    pub depth: Option<u32>,
    pub max_nodes: Option<u32>,
    pub score_threshold: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphSearchRequest {
    pub query: String,
    pub scope: String,
    #[serde(default)]
    pub options: GraphQueryOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphSearchResult {
    pub node: GraphNode,
    pub score: f64,
    pub reason: String,
    pub highlights: Vec<String>,
    pub context: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GraphQueryRequest {
    #[serde(default)]
    pub seed_ids: Vec<String>,
    #[serde(default)]
    pub seeds: Vec<GraphSeed>,
    pub query: Option<String>,
    pub scope: Option<String>,
    #[serde(default)]
    pub scope_paths: Vec<String>,
    #[serde(default, rename = "where")]
    pub where_filters: Vec<GraphWhereFilter>,
    #[serde(default)]
    pub relations: Vec<String>,
    pub view: Option<String>,
    #[serde(default)]
    pub options: GraphQueryOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphSeed {
    pub id: String,
    pub kind: String,
    pub value: String,
    pub scope: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphWhereFilter {
    pub field: String,
    pub op: String,
    pub value: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphQueryNodeResult {
    pub node: GraphNode,
    pub score: f64,
    pub depth: u32,
    pub reasons: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GraphQueryResult {
    pub seed_ids: Vec<String>,
    pub nodes: Vec<GraphQueryNodeResult>,
    pub edges: Vec<GraphEdge>,
    pub provider_id: String,
    pub diagnostics: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ContextBudget {
    pub max_nodes: Option<u32>,
    pub max_tokens: Option<u32>,
    pub include_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextPackRequest {
    pub graph_query: GraphQueryRequest,
    #[serde(default)]
    pub budget: ContextBudget,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextPackNode {
    pub node: GraphNode,
    pub score: f64,
    pub depth: u32,
    pub text: String,
    pub token_estimate: u32,
    pub reasons: Vec<String>,
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextPack {
    pub seed_ids: Vec<String>,
    pub total_token_estimate: u32,
    pub included_node_ids: Vec<String>,
    pub included_paths: Vec<String>,
    pub nodes: Vec<ContextPackNode>,
    pub edges: Vec<GraphEdge>,
    pub diagnostics: serde_json::Value,
}
