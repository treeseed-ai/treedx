from __future__ import annotations

from typing import Any

from .common import json_request, segment
from treedx_sdk.transport import Transport


class ExecAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def run(self, workspace_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/workspaces/{segment(workspace_id)}/exec", body)
