from __future__ import annotations

from typing import Any

from ..common import json_request, segment
from treedx.transport import Transport


class RepositoriesAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def register(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/repos/register", body)

    def list(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/repos")

    def create(self, body: Any) -> Any:
        return json_request(self.transport, "POST", "/api/v1/repos", body)

    def get(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}")

    def status(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/status")

    def refs(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/refs")

    def remotes(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/remotes")

    def push(self, repo_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/push", body)

    def sync(self, repo_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/sync", body)
