from __future__ import annotations

from typing import Any, Protocol


class SnapshotPort(Protocol):
    def build(self, repo_id: str, body: Any) -> Any: ...
    def get(self, repo_id: str, snapshot_id: str) -> Any: ...
