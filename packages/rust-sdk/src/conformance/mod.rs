use serde::Deserialize;

use crate::client::{OperationOptions, TreeDxClient};
use crate::transport::TreeDxHttpMethod;

#[derive(Clone, Debug, Deserialize)]
pub struct TreeDxConformanceScenario {
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
pub enum TreeDxConformanceStatus {
    Passed,
    Failed,
    NotConfigured,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TreeDxConformanceResult {
    pub scenario_id: String,
    pub status: TreeDxConformanceStatus,
    pub message: Option<String>,
}

pub struct TreeDxConformanceAdapter {
    client: TreeDxClient,
    server_configured: bool,
}

impl TreeDxConformanceAdapter {
    pub fn new(client: TreeDxClient) -> Self {
        Self {
            client,
            server_configured: false,
        }
    }

    pub fn with_server_configured(client: TreeDxClient, server_configured: bool) -> Self {
        Self {
            client,
            server_configured,
        }
    }

    pub async fn run_scenario(
        &self,
        scenario: &TreeDxConformanceScenario,
    ) -> TreeDxConformanceResult {
        if !self.server_configured {
            return TreeDxConformanceResult {
                scenario_id: scenario.id.clone(),
                status: TreeDxConformanceStatus::NotConfigured,
                message: Some("TreeDX server is not configured".to_string()),
            };
        }

        for endpoint_ref in &scenario.endpoint_refs {
            let Some((method, path)) = endpoint_ref.split_once(' ') else {
                return TreeDxConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDxConformanceStatus::Failed,
                    message: Some(format!("invalid endpoint ref: {endpoint_ref}")),
                };
            };
            let Some(method) = method_from_str(method) else {
                return TreeDxConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDxConformanceStatus::Failed,
                    message: Some(format!("unsupported endpoint method: {method}")),
                };
            };
            let mut options = OperationOptions::default();
            options.path_params.extend([
                (
                    "repo_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_REPO_ID", "repo_conformance"),
                ),
                (
                    "workspace_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_WORKSPACE_ID", "workspace_conformance"),
                ),
                (
                    "node_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_NODE_ID", "node_conformance"),
                ),
                (
                    "job_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_JOB_ID", "job_conformance"),
                ),
                (
                    "snapshot_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_SNAPSHOT_ID", "snapshot_conformance"),
                ),
                (
                    "artifact_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_ARTIFACT_ID", "artifact_conformance"),
                ),
                (
                    "mirror_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_MIRROR_ID", "mirror_conformance"),
                ),
                (
                    "migration_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_MIGRATION_ID", "migration_conformance"),
                ),
                (
                    "upload_id".to_string(),
                    env_or("TREEDX_CONFORMANCE_UPLOAD_ID", "upload_conformance"),
                ),
                (
                    "part_number".to_string(),
                    env_or("TREEDX_CONFORMANCE_PART_NUMBER", "1"),
                ),
            ]);
            if !matches!(method, TreeDxHttpMethod::Get | TreeDxHttpMethod::Delete) {
                options.body = Some(serde_json::json!({ "dryRun": true }));
            }
            if let Err(error) = self.client.operation(method, path, options).await {
                return TreeDxConformanceResult {
                    scenario_id: scenario.id.clone(),
                    status: TreeDxConformanceStatus::Failed,
                    message: Some(error.message),
                };
            }
        }

        TreeDxConformanceResult {
            scenario_id: scenario.id.clone(),
            status: TreeDxConformanceStatus::Passed,
            message: None,
        }
    }
}

fn method_from_str(method: &str) -> Option<TreeDxHttpMethod> {
    match method {
        "GET" => Some(TreeDxHttpMethod::Get),
        "POST" => Some(TreeDxHttpMethod::Post),
        "PUT" => Some(TreeDxHttpMethod::Put),
        "PATCH" => Some(TreeDxHttpMethod::Patch),
        "DELETE" => Some(TreeDxHttpMethod::Delete),
        _ => None,
    }
}

fn env_or(name: &str, fallback: &str) -> String {
    std::env::var(name).unwrap_or_else(|_| fallback.to_string())
}
