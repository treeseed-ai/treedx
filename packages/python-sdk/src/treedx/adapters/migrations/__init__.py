from __future__ import annotations

from typing import Any

from ..common import json_request, segment
from treedx.transport import Transport


class MigrationsAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def create(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/migrations", body)

    def get(self, repo_id: str, migration_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/repos/{segment(repo_id)}/migrations/{segment(migration_id)}")
