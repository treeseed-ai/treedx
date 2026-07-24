from __future__ import annotations

from typing import Any, Mapping

from ..common import json_request
from treedx.transport import Transport


class AuditAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def events(self, query: Mapping[str, str | int | float | bool | None] | None = None) -> Any:
        return json_request(self.transport, "GET", "/api/v1/audit/events", query=query)
