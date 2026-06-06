from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedx_sdk.transport import Transport


class WorkspacesAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def create(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/repos/{segment(repo_id)}/workspaces", body)

    def get(self, workspace_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}")

    def close(self, workspace_id: str, body: Any | None = None) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/close", body)
