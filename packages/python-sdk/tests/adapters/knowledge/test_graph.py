from treedx.adapters import GraphAdapter


def test_graph_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = GraphAdapter(transport)
    adapter.refresh("repo/a")
    adapter.query("repo/a", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/graph/refresh",
        "POST /api/v1/repos/repo%2Fa/graph/query",
    ]
