from __future__ import annotations

from typing import Any, Mapping

from .common import json_request, segment
from treedx_sdk.transport import Transport


class FilesAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def tree(self, workspace_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}/tree", query=query)

    def read(self, workspace_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}/files", query=query)

    def write(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "PUT", f"/api/v1/workspaces/{segment(workspace_id)}/files", body)

    def patch(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "PATCH", f"/api/v1/workspaces/{segment(workspace_id)}/files", body)

    def delete(self, workspace_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "DELETE", f"/api/v1/workspaces/{segment(workspace_id)}/files", query=query)

    def search(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/search", body)

    def status(self, workspace_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}/status")

    def diff(self, workspace_id: str, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/workspaces/{segment(workspace_id)}/diff", query=query)

    def commit(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/commit", body)
