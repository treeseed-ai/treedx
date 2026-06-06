from __future__ import annotations

from typing import Any

from .common import json_request
from treedx_sdk.transport import Transport


class ObservabilityAdapter:
    def __init__(self, transport: Transport) -> None:
        self.transport = transport

    def health(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/health")

    def ready(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/ready")

    def deep_health(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/health/deep")

    def metrics(self) -> Any:
        return json_request(self.transport, "GET", "/api/v1/metrics")
