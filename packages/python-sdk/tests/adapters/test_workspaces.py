from treedx_sdk.adapters import WorkspacesAdapter


def test_workspaces_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = WorkspacesAdapter(transport)
    adapter.create("repo/a", {})
    adapter.get("workspace/1")
    adapter.close("workspace/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/workspaces",
        "GET /api/v1/workspaces/workspace%2F1",
        "POST /api/v1/workspaces/workspace%2F1/close",
    ]
