from treedx.adapters import QueryAdapter


def test_query_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = QueryAdapter(transport)
    adapter.read_file("repo/a", {})
    adapter.list_paths("repo/a", {})
    adapter.search_files("repo/a", {})
    adapter.repository("repo/a", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/repos/repo%2Fa/files/read",
        "POST /api/v1/repos/repo%2Fa/paths/list",
        "POST /api/v1/repos/repo%2Fa/files/search",
        "POST /api/v1/repos/repo%2Fa/query",
    ]
