from __future__ import annotations

from dataclasses import dataclass
from typing import Any, BinaryIO, TypeAlias


BinaryBody: TypeAlias = bytes | bytearray | memoryview | BinaryIO


@dataclass(frozen=True)
class MultipartUpload:
    upload_id: str
    completed_parts: list[dict[str, Any]] | None = None


def is_binary_body(value: Any) -> bool:
    return isinstance(value, (bytes, bytearray, memoryview)) or callable(getattr(value, "read", None))


def to_bytes(value: BinaryBody) -> bytes:
    if isinstance(value, bytes):
        return value
    if isinstance(value, bytearray):
        return bytes(value)
    if isinstance(value, memoryview):
        return value.tobytes()
    data = value.read()
    if isinstance(data, str):
        raise TypeError("BinaryBody streams must return bytes, not text")
    return bytes(data)


def assert_binary_body(value: Any) -> None:
    if not is_binary_body(value):
        raise TypeError("Expected binary body; strings and text payloads are not binary-safe")
