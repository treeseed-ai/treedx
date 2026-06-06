use std::sync::Arc;

use serde_json::Value;

use crate::adapters::{
    AdminAdapter, ArtifactsAdapter, AuditAdapter, BlobsAdapter, ContextAdapter, ExecAdapter,
    FederationAdapter, FederationInternalAdapter, FilesAdapter, GraphAdapter, MigrationsAdapter,
    MirrorsAdapter, ObservabilityAdapter, PolicyAdapter, QueryAdapter, RegistryAdapter,
    RepositoriesAdapter, SearchIndexAdapter, SnapshotsAdapter, WorkspacesAdapter,
};
use crate::config::TreeDbConfig;
use crate::error::TreeDbResult;
use crate::generated::openapi_types::TREE_DB_OPENAPI_OPERATIONS;
use crate::transport::{ReqwestTransport, Transport, TreeDbHttpMethod};

#[derive(Clone)]
pub struct TreeDbClient {
    config: TreeDbConfig,
    transport: Arc<dyn Transport>,
    repositories: RepositoriesAdapter,
    workspaces: WorkspacesAdapter,
    files: FilesAdapter,
    blobs: BlobsAdapter,
    query: QueryAdapter,
    graph: GraphAdapter,
    context: ContextAdapter,
    federation: FederationAdapter,
    registry: RegistryAdapter,
    snapshots: SnapshotsAdapter,
    artifacts: ArtifactsAdapter,
    mirrors: MirrorsAdapter,
    migrations: MigrationsAdapter,
    exec: ExecAdapter,
    observability: ObservabilityAdapter,
    admin: AdminAdapter,
    audit: AuditAdapter,
    policy: PolicyAdapter,
    search_index: SearchIndexAdapter,
    federation_internal: FederationInternalAdapter,
}

impl TreeDbClient {
    pub fn new(config: TreeDbConfig) -> Self {
        let transport = Arc::new(ReqwestTransport::new(config.clone()));
        Self::with_transport(config, transport)
    }

    pub fn with_transport(config: TreeDbConfig, transport: Arc<dyn Transport>) -> Self {
        Self {
            config,
            repositories: RepositoriesAdapter::new(transport.clone()),
            workspaces: WorkspacesAdapter::new(transport.clone()),
            files: FilesAdapter::new(transport.clone()),
            blobs: BlobsAdapter::new(transport.clone()),
            query: QueryAdapter::new(transport.clone()),
            graph: GraphAdapter::new(transport.clone()),
            context: ContextAdapter::new(transport.clone()),
            federation: FederationAdapter::new(transport.clone()),
            registry: RegistryAdapter::new(transport.clone()),
            snapshots: SnapshotsAdapter::new(transport.clone()),
            artifacts: ArtifactsAdapter::new(transport.clone()),
            mirrors: MirrorsAdapter::new(transport.clone()),
            migrations: MigrationsAdapter::new(transport.clone()),
            exec: ExecAdapter::new(transport.clone()),
            observability: ObservabilityAdapter::new(transport.clone()),
            admin: AdminAdapter::new(transport.clone()),
            audit: AuditAdapter::new(transport.clone()),
            policy: PolicyAdapter::new(transport.clone()),
            search_index: SearchIndexAdapter::new(transport.clone()),
            federation_internal: FederationInternalAdapter::new(transport.clone()),
            transport,
        }
    }

    pub fn config(&self) -> &TreeDbConfig {
        &self.config
    }
    pub fn transport(&self) -> &Arc<dyn Transport> {
        &self.transport
    }
    pub fn repositories(&self) -> &RepositoriesAdapter {
        &self.repositories
    }
    pub fn workspaces(&self) -> &WorkspacesAdapter {
        &self.workspaces
    }
    pub fn files(&self) -> &FilesAdapter {
        &self.files
    }
    pub fn blobs(&self) -> &BlobsAdapter {
        &self.blobs
    }
    pub fn query(&self) -> &QueryAdapter {
        &self.query
    }
    pub fn graph(&self) -> &GraphAdapter {
        &self.graph
    }
    pub fn context(&self) -> &ContextAdapter {
        &self.context
    }
    pub fn federation(&self) -> &FederationAdapter {
        &self.federation
    }
    pub fn registry(&self) -> &RegistryAdapter {
        &self.registry
    }
    pub fn snapshots(&self) -> &SnapshotsAdapter {
        &self.snapshots
    }
    pub fn artifacts(&self) -> &ArtifactsAdapter {
        &self.artifacts
    }
    pub fn mirrors(&self) -> &MirrorsAdapter {
        &self.mirrors
    }
    pub fn migrations(&self) -> &MigrationsAdapter {
        &self.migrations
    }
    pub fn exec(&self) -> &ExecAdapter {
        &self.exec
    }
    pub fn observability(&self) -> &ObservabilityAdapter {
        &self.observability
    }
    pub fn admin(&self) -> &AdminAdapter {
        &self.admin
    }
    pub fn audit(&self) -> &AuditAdapter {
        &self.audit
    }
    pub fn policy(&self) -> &PolicyAdapter {
        &self.policy
    }
    pub fn search_index(&self) -> &SearchIndexAdapter {
        &self.search_index
    }
    pub fn federation_internal(&self) -> &FederationInternalAdapter {
        &self.federation_internal
    }

    pub async fn health(&self) -> TreeDbResult<Value> {
        self.observability.health().await
    }
    pub async fn version(&self) -> TreeDbResult<Value> {
        crate::adapters::common::json_request(
            &self.transport,
            crate::transport::TreeDbHttpMethod::Get,
            "/api/v1/version",
            None,
            None,
        )
        .await
    }
    pub async fn whoami(&self) -> TreeDbResult<Value> {
        crate::adapters::common::json_request(
            &self.transport,
            crate::transport::TreeDbHttpMethod::Get,
            "/api/v1/auth/whoami",
            None,
            None,
        )
        .await
    }
    pub async fn effective_scope(&self) -> TreeDbResult<Value> {
        crate::adapters::common::json_request(
            &self.transport,
            crate::transport::TreeDbHttpMethod::Get,
            "/api/v1/policy/effective-scope",
            None,
            None,
        )
        .await
    }

    pub async fn auth_mode(&self) -> TreeDbResult<Value> {
        crate::adapters::common::json_request(
            &self.transport,
            TreeDbHttpMethod::Get,
            "/api/v1/auth/mode",
            None,
            None,
        )
        .await
    }

    pub async fn create_dev_token(&self, body: Option<Value>) -> TreeDbResult<Value> {
        crate::adapters::common::json_request(
            &self.transport,
            TreeDbHttpMethod::Post,
            "/api/v1/auth/dev-token",
            body,
            None,
        )
        .await
    }

    pub async fn operation(
        &self,
        method: TreeDbHttpMethod,
        path: &str,
        options: OperationOptions,
    ) -> TreeDbResult<Value> {
        let method_name = method.as_str();
        if !TREE_DB_OPENAPI_OPERATIONS
            .iter()
            .any(|operation| operation.method == method_name && operation.path == path)
        {
            return Err(crate::error::TreeDbApiError::network(format!(
                "unknown TreeDB OpenAPI operation: {method_name} {path}"
            )));
        }
        let mut resolved = path.to_string();
        for name in path.match_indices('{').filter_map(|(start, _)| {
            let rest = &path[start + 1..];
            rest.find('}').map(|end| &rest[..end])
        }) {
            let value = options.path_params.get(name).ok_or_else(|| {
                crate::error::TreeDbApiError::network(format!(
                    "missing path parameter {name} for {method_name} {path}"
                ))
            })?;
            resolved = resolved.replace(
                &format!("{{{name}}}"),
                &crate::adapters::common::segment(value),
            );
        }
        crate::adapters::common::json_request(
            &self.transport,
            method,
            resolved,
            options.body,
            Some(options.query),
        )
        .await
    }
}

#[derive(Clone, Debug, Default)]
pub struct OperationOptions {
    pub path_params: std::collections::BTreeMap<String, String>,
    pub query: std::collections::BTreeMap<String, String>,
    pub body: Option<Value>,
}

#[derive(Clone)]
pub struct TreeDbRegistryClient {
    registry: RegistryAdapter,
}

impl TreeDbRegistryClient {
    pub fn new(client: &TreeDbClient) -> Self {
        Self {
            registry: client.registry().clone(),
        }
    }

    pub fn registry(&self) -> &RegistryAdapter {
        &self.registry
    }
}

#[derive(Clone)]
pub struct TreeDbFederatedClient {
    federation: FederationAdapter,
}

impl TreeDbFederatedClient {
    pub fn new(client: &TreeDbClient) -> Self {
        Self {
            federation: client.federation().clone(),
        }
    }

    pub fn federation(&self) -> &FederationAdapter {
        &self.federation
    }
}
