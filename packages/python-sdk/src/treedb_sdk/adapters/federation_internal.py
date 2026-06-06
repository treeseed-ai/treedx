from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedb_sdk.transport import Transport


class FederationInternalAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def health(self) -> Any: return json_request(self.transport, "GET", "/api/v1/internal/federation/health")
    def proxy(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/internal/federation/proxy", body)
    def export_mirror(self, repo_id: str, body: Any) -> Any: return json_request(self.transport, "POST", f"/api/v1/internal/federation/repos/{segment(repo_id)}/mirror/export", body)
    def import_mirror(self, repo_id: str, body: Any) -> Any: return json_request(self.transport, "POST", f"/api/v1/internal/federation/repos/{segment(repo_id)}/mirror/import", body)
