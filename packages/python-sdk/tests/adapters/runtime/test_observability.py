from treedx.adapters import ObservabilityAdapter


def test_observability_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = ObservabilityAdapter(transport)
    adapter.health()
    adapter.ready()
    adapter.deep_health()
    adapter.metrics()
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "GET /api/v1/health",
        "GET /api/v1/ready",
        "GET /api/v1/health/deep",
        "GET /api/v1/metrics",
    ]
