from __future__ import annotations

from typing import Any, Mapping

from .common import json_request
from treedb_sdk.transport import Transport


class PolicyAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def capabilities(self) -> Any: return json_request(self.transport, "GET", "/api/v1/policy/capabilities")
    def grants(self, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any: return json_request(self.transport, "GET", "/api/v1/policy/grants", query=query)
    def create_grant(self, body: Any) -> Any: return json_request(self.transport, "POST", "/api/v1/policy/grants", body)
    def refresh(self, body: Any | None = None) -> Any: return json_request(self.transport, "POST", "/api/v1/policy/refresh", body)
