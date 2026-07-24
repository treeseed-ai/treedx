from __future__ import annotations

from typing import Any, Protocol


class BlobPort(Protocol):
    def read(self, repo_id: str, body: Any) -> Any: ...
    def upload(self, workspace_id: str, binary_body: Any, query: Any = None) -> Any: ...
