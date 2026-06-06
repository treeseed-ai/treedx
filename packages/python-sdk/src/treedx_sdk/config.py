from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

from .auth import AuthProvider
from .transport import Transport


@dataclass(frozen=True)
class TreeDxClientConfig:
    base_url: str
    token: str | None = None
    auth_provider: AuthProvider | None = None
    transport: Transport | None = None
    default_headers: Mapping[str, str] | None = None
    timeout: float | None = None
