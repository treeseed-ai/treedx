from __future__ import annotations

from typing import Any, Protocol


class MirrorPort(Protocol):
    def list(self, repo_id: str) -> Any: ...
    def sync(self, repo_id: str, mirror_id: str, body: Any = None) -> Any: ...
