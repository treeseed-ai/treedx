from __future__ import annotations

from typing import Any, Protocol


class QueryPort(Protocol):
    def read_file(self, repo_id: str, body: Any) -> Any: ...
    def search_files(self, repo_id: str, body: Any) -> Any: ...
