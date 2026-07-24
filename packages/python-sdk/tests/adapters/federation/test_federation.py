from treedx.adapters import FederationAdapter


def test_federation_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = FederationAdapter(transport)
    adapter.plan({})
    adapter.search({})
    adapter.query({})
    adapter.context_build({})
    adapter.graph_query({})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/federation/query/plan",
        "POST /api/v1/search",
        "POST /api/v1/query",
        "POST /api/v1/context/build",
        "POST /api/v1/graph/query",
    ]
