from treedx_sdk import TreeDxClient
from treedx_sdk.adapters import (
    ArtifactsAdapter,
    BlobsAdapter,
    ContextAdapter,
    ExecAdapter,
    FederationAdapter,
    FilesAdapter,
    GraphAdapter,
    MigrationsAdapter,
    MirrorsAdapter,
    ObservabilityAdapter,
    QueryAdapter,
    RegistryAdapter,
    RepositoriesAdapter,
    SnapshotsAdapter,
    WorkspacesAdapter,
)
from treedx_sdk.transport import TreeDxRequest, TreeDxResponse


class MockTransport:
    def __init__(self) -> None:
        self.requests: list[TreeDxRequest] = []

    def request(self, request: TreeDxRequest) -> TreeDxResponse[object]:
        self.requests.append(request)
        return TreeDxResponse(status=200, headers={}, data={"ok": True})

    def last(self) -> TreeDxRequest:
        return self.requests[-1]


def test_client_creates_module_adapters() -> None:
    client = TreeDxClient(base_url="http://treedx.test", transport=MockTransport())
    assert isinstance(client.repositories, RepositoriesAdapter)
    assert isinstance(client.workspaces, WorkspacesAdapter)
    assert isinstance(client.files, FilesAdapter)
    assert isinstance(client.blobs, BlobsAdapter)
    assert isinstance(client.query, QueryAdapter)
    assert isinstance(client.graph, GraphAdapter)
    assert isinstance(client.context, ContextAdapter)
    assert isinstance(client.federation, FederationAdapter)
    assert isinstance(client.registry, RegistryAdapter)
    assert isinstance(client.snapshots, SnapshotsAdapter)
    assert isinstance(client.artifacts, ArtifactsAdapter)
    assert isinstance(client.mirrors, MirrorsAdapter)
    assert isinstance(client.migrations, MigrationsAdapter)
    assert isinstance(client.exec, ExecAdapter)
    assert isinstance(client.observability, ObservabilityAdapter)


def test_client_uses_custom_transport() -> None:
    transport = MockTransport()
    client = TreeDxClient(base_url="http://treedx.test", transport=transport)
    client.health()
    assert transport.last().path == "/api/v1/health"
