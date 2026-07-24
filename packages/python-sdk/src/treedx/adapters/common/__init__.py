from __future__ import annotations

from typing import Any, Mapping
from urllib.parse import quote

from treedx.binary import BinaryBody
from treedx.transport import Transport, TreeDxHttpMethod, TreeDxRequest


def segment(value: str) -> str:
    return quote(str(value), safe="")


def json_request(
    transport: Transport,
    method: TreeDxHttpMethod,
    path: str,
    body: Any | None = None,
    query: Mapping[str, str | int | float | bool | None] | None = None,
) -> Any:
    return transport.request(TreeDxRequest(method=method, path=path, body=body, query=query)).data


def binary_request(
    transport: Transport,
    method: TreeDxHttpMethod,
    path: str,
    body: BinaryBody,
    query: Mapping[str, str | int | float | bool | None] | None = None,
) -> Any:
    return transport.request(TreeDxRequest(method=method, path=path, binary_body=body, query=query)).data
