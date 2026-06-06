from __future__ import annotations

from typing import Any

import pytest

from treedx_sdk.transport import TreeDxRequest, TreeDxResponse


class _MockTransport:
    def __init__(self) -> None:
        self.requests: list[TreeDxRequest] = []

    def request(self, request: TreeDxRequest) -> TreeDxResponse[Any]:
        self.requests.append(request)
        return TreeDxResponse(status=200, headers={}, data={"ok": True})

    def last(self) -> TreeDxRequest:
        if not self.requests:
            raise AssertionError("No request recorded")
        return self.requests[-1]


@pytest.fixture
def MockTransport() -> type[_MockTransport]:
    return _MockTransport
