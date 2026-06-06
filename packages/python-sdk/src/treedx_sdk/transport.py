from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Generic, Literal, Mapping, Protocol, TypeVar
from urllib.parse import urljoin

import httpx

from .auth import resolve_authorization_header
from .binary import BinaryBody
from .errors import TreeDxApiError


T = TypeVar("T")
TreeDxHttpMethod = Literal["GET", "POST", "PUT", "PATCH", "DELETE"]


@dataclass(frozen=True)
class TreeDxRequest:
    method: TreeDxHttpMethod
    path: str
    query: Mapping[str, str | int | float | bool | None] | None = None
    headers: Mapping[str, str] | None = None
    body: Any | None = None
    binary_body: BinaryBody | None = None


@dataclass(frozen=True)
class TreeDxResponse(Generic[T]):
    status: int
    headers: Mapping[str, str]
    data: T


class Transport(Protocol):
    def request(self, request: TreeDxRequest) -> TreeDxResponse[Any]: ...


class HttpxTransport:
    def __init__(
        self,
        config: object,
    ) -> None:
        self.config = config

    def request(self, request: TreeDxRequest) -> TreeDxResponse[Any]:
        base_url = str(getattr(self.config, "base_url"))
        url = urljoin(base_url.rstrip("/") + "/", request.path.lstrip("/"))
        headers: dict[str, str] = {
            **(dict(getattr(self.config, "default_headers", None) or {})),
            **resolve_authorization_header(self.config),
            **(dict(request.headers or {})),
        }
        params = {key: value for key, value in dict(request.query or {}).items() if value is not None}
        timeout = getattr(self.config, "timeout", None)
        try:
            with httpx.Client(timeout=timeout) as client:
                response = client.request(
                    request.method,
                    url,
                    params=params,
                    headers=headers,
                    json=request.body if request.binary_body is None else None,
                    content=request.binary_body if request.binary_body is not None else None,
                )
        except httpx.HTTPError as error:
            raise TreeDxApiError.network("TreeDX network request failed", error) from error

        data = _parse_response_body(response)
        if response.status_code < 200 or response.status_code >= 300:
            raise TreeDxApiError.from_response(response.status_code, data)
        return TreeDxResponse(status=response.status_code, headers=dict(response.headers), data=data)


def _parse_response_body(response: httpx.Response) -> Any:
    if response.status_code == 204:
        return None
    content_type = response.headers.get("content-type", "")
    if "application/json" in content_type:
        return response.json()
    if content_type.startswith("text/"):
        return response.text
    return response.content
