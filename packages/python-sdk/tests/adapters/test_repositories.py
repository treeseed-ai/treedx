from treedx_sdk.adapters import RepositoriesAdapter


def test_repositories_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = RepositoriesAdapter(transport)
    adapter.register({})
    adapter.get("repo/a")
    adapter.refs("repo/a")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/register",
        "GET /api/v1/repos/repo%2Fa",
        "GET /api/v1/repos/repo%2Fa/refs",
    ]
