from __future__ import annotations

from typing import Any, Protocol


class MigrationPort(Protocol):
    def create(self, repo_id: str, body: Any) -> Any: ...
    def get(self, repo_id: str, migration_id: str) -> Any: ...
