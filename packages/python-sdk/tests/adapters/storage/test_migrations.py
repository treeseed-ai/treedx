from treedx.adapters import MigrationsAdapter


def test_migrations_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = MigrationsAdapter(transport)
    adapter.create("repo/a", {})
    adapter.get("repo/a", "migration/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/migrations",
        "GET /api/v1/repos/repo%2Fa/migrations/migration%2F1",
    ]
