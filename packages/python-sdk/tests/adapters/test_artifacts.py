from treedx_sdk.adapters import ArtifactsAdapter


def test_artifacts_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = ArtifactsAdapter(transport)
    adapter.export("repo/a", {})
    adapter.list("repo/a")
    adapter.get("repo/a", "artifact/1")
    adapter.delete("repo/a", "artifact/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/artifacts/export",
        "GET /api/v1/repos/repo%2Fa/artifacts",
        "GET /api/v1/repos/repo%2Fa/artifacts/artifact%2F1",
        "DELETE /api/v1/repos/repo%2Fa/artifacts/artifact%2F1",
    ]
