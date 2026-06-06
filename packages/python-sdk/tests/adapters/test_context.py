from treedx_sdk.adapters import ContextAdapter


def test_context_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = ContextAdapter(transport)
    adapter.build("repo/a", {})
    adapter.parse("repo/a", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/context/build",
        "POST /api/v1/repos/repo%2Fa/context/parse-ctx",
    ]
