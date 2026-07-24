from treedx.adapters import ExecAdapter


def test_exec_endpoints(MockTransport) -> None:  # type: ignore[no-untyped-def]
    transport = MockTransport()
    adapter = ExecAdapter(transport)
    adapter.run("workspace/1", {})
    assert [f"{request.method} {request.path}" for request in transport.requests] == [
        "POST /api/v1/workspaces/workspace%2F1/exec",
    ]
