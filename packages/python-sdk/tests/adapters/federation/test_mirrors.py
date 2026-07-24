from treedx.adapters import MirrorsAdapter


def test_mirrors_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = MirrorsAdapter(transport)
    adapter.list("repo/a")
    adapter.upsert("repo/a", {})
    adapter.sync("repo/a", "mirror/1")
    adapter.health("repo/a", "mirror/1")
    adapter.promote("repo/a", "mirror/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "GET /api/v1/repos/repo%2Fa/mirrors",
        "POST /api/v1/repos/repo%2Fa/mirrors",
        "POST /api/v1/repos/repo%2Fa/mirrors/mirror%2F1/sync",
        "POST /api/v1/repos/repo%2Fa/mirrors/mirror%2F1/health",
        "POST /api/v1/repos/repo%2Fa/mirrors/mirror%2F1/promote",
    ]
