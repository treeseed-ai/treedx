from __future__ import annotations

from typing import Any

from ..common import json_request, segment
from treedx.transport import Transport


class RegistryAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def local_node(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/node")

    def nodes(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/registry/nodes")

    def get_placement(self, repo_id: str) -> Any:
        return json_request(self.transport, "GET", f"/api/v1/registry/repos/{segment(repo_id)}/placement")

    def set_placement(self, repo_id: str, body: Any) -> Any:
        return json_request(self.transport, "POST", f"/api/v1/registry/repos/{segment(repo_id)}/placement", body)
