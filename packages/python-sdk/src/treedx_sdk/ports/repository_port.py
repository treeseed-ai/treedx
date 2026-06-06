from __future__ import annotations

from typing import Any, Protocol


class RepositoryPort(Protocol):
    def list(self) -> Any: ...
    def get(self, repo_id: str) -> Any: ...
