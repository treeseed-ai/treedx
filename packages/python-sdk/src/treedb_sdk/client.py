from __future__ import annotations

from typing import Any, Mapping
import re

from .adapters import (
    AdminAdapter,
    AuditAdapter,
    ArtifactsAdapter,
    BlobsAdapter,
    ContextAdapter,
    ExecAdapter,
    FederationAdapter,
    FederationInternalAdapter,
    FilesAdapter,
    GraphAdapter,
    MigrationsAdapter,
    MirrorsAdapter,
    ObservabilityAdapter,
    PolicyAdapter,
    QueryAdapter,
    RegistryAdapter,
    RepositoriesAdapter,
    SearchIndexAdapter,
    SnapshotsAdapter,
    WorkspacesAdapter,
)
from .auth import AuthProvider
from .config import TreeDbClientConfig
from .transport import HttpxTransport, Transport, TreeDbRequest
from .generated import TREE_DB_OPENAPI_OPERATIONS
from .binary import BinaryBody
from .adapters.common import segment


class TreeDbClient:
    def __init__(
        self,
        base_url: str,
        token: str | None = None,
        auth_provider: AuthProvider | None = None,
        transport: Transport | None = None,
        default_headers: Mapping[str, str] | None = None,
        timeout: float | None = None,
    ) -> None:
        self.config = TreeDbClientConfig(
            base_url=base_url,
            token=token,
            auth_provider=auth_provider,
            transport=transport,
            default_headers=default_headers,
            timeout=timeout,
        )
        self.transport = transport or HttpxTransport(self.config)
        self.repositories = RepositoriesAdapter(self.transport)
        self.workspaces = WorkspacesAdapter(self.transport)
        self.files = FilesAdapter(self.transport)
        self.blobs = BlobsAdapter(self.transport)
        self.query = QueryAdapter(self.transport)
        self.graph = GraphAdapter(self.transport)
        self.context = ContextAdapter(self.transport)
        self.federation = FederationAdapter(self.transport)
        self.registry = RegistryAdapter(self.transport)
        self.snapshots = SnapshotsAdapter(self.transport)
        self.artifacts = ArtifactsAdapter(self.transport)
        self.mirrors = MirrorsAdapter(self.transport)
        self.migrations = MigrationsAdapter(self.transport)
        self.exec = ExecAdapter(self.transport)
        self.observability = ObservabilityAdapter(self.transport)
        self.admin = AdminAdapter(self.transport)
        self.audit = AuditAdapter(self.transport)
        self.policy = PolicyAdapter(self.transport)
        self.search_index = SearchIndexAdapter(self.transport)
        self.federation_internal = FederationInternalAdapter(self.transport)

    def health(self) -> Any:
        return self.observability.health()

    def version(self) -> Any:
        return self.transport.request(TreeDbRequest(method="GET", path="/api/v1/version")).data

    def whoami(self) -> Any:
        return self.transport.request(TreeDbRequest(method="GET", path="/api/v1/auth/whoami")).data

    def effective_scope(self) -> Any:
        return self.transport.request(TreeDbRequest(method="GET", path="/api/v1/policy/effective-scope")).data

    def auth_mode(self) -> Any:
        return self.transport.request(TreeDbRequest(method="GET", path="/api/v1/auth/mode")).data

    def create_dev_token(self, body: Any | None = None) -> Any:
        return self.transport.request(TreeDbRequest(method="POST", path="/api/v1/auth/dev-token", body=body)).data

    def operation(
        self,
        method: str,
        path: str,
        path_params: Mapping[str, str | int] | None = None,
        query: Mapping[str, str | int | float | bool | None] | None = None,
        body: Any | None = None,
        binary_body: BinaryBody | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> Any:
        if not any(operation["method"] == method and operation["path"] == path for operation in TREE_DB_OPENAPI_OPERATIONS):
            raise ValueError(f"Unknown TreeDB OpenAPI operation: {method} {path}")
        resolved = path
        for name in re.findall(r"\{([^}]+)\}", path):
            if path_params is None or name not in path_params:
                raise ValueError(f"Missing path parameter {name} for {method} {path}")
            resolved = resolved.replace("{" + name + "}", segment(str(path_params[name])))
        return self.transport.request(TreeDbRequest(method=method, path=resolved, query=query, body=body, binary_body=binary_body, headers=headers)).data


class TreeDbRegistryClient:
    def __init__(self, client: TreeDbClient) -> None:
        self.client = client
        self.registry = client.registry


class TreeDbFederatedClient:
    def __init__(self, client: TreeDbClient) -> None:
        self.client = client
        self.federation = client.federation
