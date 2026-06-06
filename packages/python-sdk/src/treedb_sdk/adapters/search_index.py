from __future__ import annotations

from typing import Any, Mapping

from .common import json_request, segment
from treedb_sdk.transport import Transport


class SearchIndexAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def status(self, repo_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/search/index/status", query=query)

    def refresh(self, repo_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/search/index/refresh", body)

    def compact(self, repo_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/search/index/compact", body)
