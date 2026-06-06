from treedx_sdk.adapters import RegistryAdapter


def test_registry_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = RegistryAdapter(transport)
    adapter.local_node()
    adapter.nodes()
    adapter.get_placement("repo/a")
    adapter.set_placement("repo/a", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "GET /api/v1/node",
        "GET /api/v1/registry/nodes",
        "GET /api/v1/registry/repos/repo%2Fa/placement",
        "POST /api/v1/registry/repos/repo%2Fa/placement",
    ]
