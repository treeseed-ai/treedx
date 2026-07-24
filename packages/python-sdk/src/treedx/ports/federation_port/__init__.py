from __future__ import annotations

from typing import Any, Protocol


class FederationPort(Protocol):
    def search(self, body: Any) -> Any: ...
    def query(self, body: Any) -> Any: ...
