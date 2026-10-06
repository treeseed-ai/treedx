from __future__ import annotations

from typing import Any, Protocol


class ArtifactPort(Protocol):
    def list(self, repo_id: str) -> Any: ...
    def get(self, repo_id: str, artifact_id: str) -> Any: ...
