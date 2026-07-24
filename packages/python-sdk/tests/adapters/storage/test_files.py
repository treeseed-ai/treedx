from treedx.adapters import FilesAdapter


def test_files_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = FilesAdapter(transport)
    adapter.tree("workspace/1")
    adapter.read("workspace/1")
    adapter.write("workspace/1", {})
    adapter.patch("workspace/1", {})
    adapter.delete("workspace/1")
    adapter.commit("workspace/1", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "GET /api/v1/workspaces/workspace%2F1/tree",
        "GET /api/v1/workspaces/workspace%2F1/files",
        "PUT /api/v1/workspaces/workspace%2F1/files",
        "PATCH /api/v1/workspaces/workspace%2F1/files",
        "DELETE /api/v1/workspaces/workspace%2F1/files",
        "POST /api/v1/workspaces/workspace%2F1/commit",
    ]
