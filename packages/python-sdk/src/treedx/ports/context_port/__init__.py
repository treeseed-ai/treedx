from __future__ import annotations

from typing import Any, Protocol


class ContextPort(Protocol):
    def build(self, repo_id: str, body: Any) -> Any: ...
    def parse(self, repo_id: str, body: Any) -> Any: ...
