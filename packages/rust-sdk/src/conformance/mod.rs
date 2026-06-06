use serde::Deserialize;

use crate::client::{OperationOptions, TreeDbClient};
use crate::transport::TreeDbHttpMethod;

#[derive(Clone, Debug, Deserialize)]
pub struct TreeDbConformanceScenario {
    pub id: String,
    #[serde(rename = "capabilityId")]
    pub capability_id: String,
    pub title: String,
    pub required: bool,
    #[serde(rename = "endpointRefs")]
    pub endpoint_refs: Vec<String>,
    pub steps: Vec<serde_json::Value>,
    pub assertions: Vec<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TreeDbConformanceStatus {
    Passed,
    Failed,
    NotConfigured,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TreeDbConformanceResult {
    pub scenario_id: String,
    pub status: TreeDbConformanceStatus,
    pub message: Option<String>,
}

pub struct TreeDbConformanceAdapter {
    client: TreeDbClient,
    server_configured: bool,
}

impl TreeDbConformanceAdapter {
    pub fn new(client: TreeDbClient) -> Self {
        Self {
            client,
            server_configured: false,
        }
    }

    pub fn with_server_configured(client: TreeDbClient, server_configured: bool) -> Self {
        Self {
            client,
            server_configured,
        }
    }

    pub async fn run_scenario(
        &self,
        scenario: &TreeDbConformanceScenario,
    ) -> TreeDbConformanceResult {
        if !self.server_configured {
            return TreeDbConformanceResult {
                scenario_id: scenario.id.clone(),
                status: TreeDbConformanceStatus::NotConfigured,
                message: Some("TreeDB server is not configured".to_string()),
            };
        }

        for endpoint_ref in &scenario.endpoint_refs {
            let Some((method, path)) = endpoint_ref.split_once(' ') else {
                return TreeDbConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDbConformanceStatus::Failed,
                    message: Some(format!("invalid endpoint ref: {endpoint_ref}")),
                };
            };
            let Some(method) = method_from_str(method) else {
                return TreeDbConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDbConformanceStatus::Failed,
                    message: Some(format!("unsupported endpoint method: {method}")),
                };
            };
            let mut options = OperationOptions::default();
            options.path_params.extend([
                (
                    "repo_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_REPO_ID", "repo_conformance"),
                ),
                (
                    "workspace_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_WORKSPACE_ID", "workspace_conformance"),
                ),
                (
                    "node_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_NODE_ID", "node_conformance"),
                ),
                (
                    "job_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_JOB_ID", "job_conformance"),
                ),
                (
                    "snapshot_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_SNAPSHOT_ID", "snapshot_conformance"),
                ),
                (
                    "artifact_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_ARTIFACT_ID", "artifact_conformance"),
                ),
                (
                    "mirror_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_MIRROR_ID", "mirror_conformance"),
                ),
                (
                    "migration_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_MIGRATION_ID", "migration_conformance"),
                ),
                (
                    "upload_id".to_string(),
                    env_or("TREEDB_CONFORMANCE_UPLOAD_ID", "upload_conformance"),
                ),
                (
                    "part_number".to_string(),
                    env_or("TREEDB_CONFORMANCE_PART_NUMBER", "1"),
                ),
            ]);
            if !matches!(method, TreeDbHttpMethod::Get | TreeDbHttpMethod::Delete) {
                options.body = Some(serde_json::json!({ "dryRun": true }));
            }
            if let Err(error) = self.client.operation(method, path, options).await {
                return TreeDbConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDbConformanceStatus::Failed,
                    message: Some(error.message),
                };
            }
        }

        TreeDbConformanceResult {
            scenario_id: scenario.id.clone(),
            status: TreeDbConformanceStatus::Passed,
            message: None,
        }
    }
}

fn method_from_str(method: &str) -> Option<TreeDbHttpMethod> {
    match method {
        "GET" => Some(TreeDbHttpMethod::Get),
        "POST" => Some(TreeDbHttpMethod::Post),
        "PUT" => Some(TreeDbHttpMethod::Put),
        "PATCH" => Some(TreeDbHttpMethod::Patch),
        "DELETE" => Some(TreeDbHttpMethod::Delete),
        _ => None,
    }
}

fn env_or(name: &str, fallback: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| fallback.to_string())
}
