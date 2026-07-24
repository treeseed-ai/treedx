from __future__ import annotations

from typing import Any

from ..common import json_request, segment
from treedx.transport import Transport


class MirrorsAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def list(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/mirrors")

    def upsert(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/mirrors", body)

    def sync(self, repo_id: str, mirror_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/mirrors/{segment(mirror_id)}/sync", body)

    def health(self, repo_id: str, mirror_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/mirrors/{segment(mirror_id)}/health", body)

    def promote(self, repo_id: str, mirror_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/mirrors/{segment(mirror_id)}/promote", body)
