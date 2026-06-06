from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedx_sdk.transport import Transport


class QueryAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def read_file(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/files/read", body)

    def list_paths(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/paths/list", body)

    def search_files(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/files/search", body)

    def repository(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/query", body)
