from __future__ import annotations

from typing import Any, Protocol


class WorkspacePort(Protocol):
    def create(self, repo_id: str, body: Any) -> Any: ...
    def get(self, workspace_id: str) -> Any: ...
