from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable


@runtime_checkable
class AuthProvider(Protocol):
    def get_token(self) -> str: ...


@dataclass(frozen=True)
class StaticBearerTokenAuthProvider:
    token: str

    def get_token(self) -> str:
        return self.token


def create_auth_provider(token_or_provider: str | AuthProvider | None) -> AuthProvider | None:
    if token_or_provider is None:
        return None
    if isinstance(token_or_provider, str):
        return StaticBearerTokenAuthProvider(token_or_provider)
    return token_or_provider


def resolve_authorization_header(config: object) -> dict[str, str]:
    provider = getattr(config, "auth_provider", None) or create_auth_provider(getattr(config, "token", None))
    if provider is None:
        return {}
    token = provider.get_token()
    if not token:
        return {}
    return {"Authorization": f"Bearer {token}"}
