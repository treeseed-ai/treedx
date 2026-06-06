from treedx_sdk.adapters import SnapshotsAdapter


def test_snapshots_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = SnapshotsAdapter(transport)
    adapter.build("repo/a", {})
    adapter.get("repo/a", "snapshot/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/snapshots/build",
        "GET /api/v1/repos/repo%2Fa/snapshots/snapshot%2F1",
    ]
