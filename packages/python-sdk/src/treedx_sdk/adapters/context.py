from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedx_sdk.transport import Transport


class ContextAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def build(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/context/build", body)

    def parse(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/context/parse-ctx", body)
