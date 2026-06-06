from __future__ import annotations

from typing import Any, Protocol


class ExecPort(Protocol):
    def run(self, workspace_id: str, body: Any) -> Any: ...
