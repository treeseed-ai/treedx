from __future__ import annotations

from typing import Any, Protocol


class GraphPort(Protocol):
    def refresh(self, repo_id: str, body: Any = None) -> Any: ...
    def query(self, repo_id: str, body: Any) -> Any: ...
