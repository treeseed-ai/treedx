from treedx_sdk.adapters import BlobsAdapter


def test_blobs_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = BlobsAdapter(transport)
    adapter.read("repo/a", {})
    adapter.write("workspace/1", {})
    adapter.download("workspace/1")
    adapter.upload("workspace/1", b"abc")
    adapter.create_multipart_upload("workspace/1", {})
    adapter.upload_part("workspace/1", "upload/1", 2, b"abc")
    adapter.complete_multipart_upload("workspace/1", "upload/1", {})
    adapter.abort_multipart_upload("workspace/1", "upload/1")
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/blobs/read",
        "POST /api/v1/workspaces/workspace%2F1/blobs/write",
        "GET /api/v1/workspaces/workspace%2F1/blobs/download",
        "PUT /api/v1/workspaces/workspace%2F1/blobs/upload",
        "POST /api/v1/workspaces/workspace%2F1/blobs/uploads",
        "PUT /api/v1/workspaces/workspace%2F1/blobs/uploads/upload%2F1/parts/2",
        "POST /api/v1/workspaces/workspace%2F1/blobs/uploads/upload%2F1/complete",
        "DELETE /api/v1/workspaces/workspace%2F1/blobs/uploads/upload%2F1",
    ]
