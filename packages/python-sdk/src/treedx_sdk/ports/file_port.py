from __future__ import annotations

from typing import Any, Protocol


class FilePort(Protocol):
    def read(self, workspace_id: str, query: Any = None) -> Any: ...
    def write(self, workspace_id: str, body: Any) -> Any: ...
