from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Generic, TypeAlias, TypeVar


T = TypeVar("T")
TreeDxCursor: TypeAlias = str


@dataclass(frozen=True)
class TreeDxPage(Generic[T]):
    items: list[T]
    next_cursor: str | None = None
    has_more: bool | None = None
    cursor: str | None = None
    limit: int | None = None


def create_page(
    items: list[T],
    *,
    next_cursor: str | None = None,
    has_more: bool | None = None,
    cursor: str | None = None,
    limit: int | None = None,
) -> TreeDxPage[T]:
    return TreeDxPage(items=items, next_cursor=next_cursor, has_more=has_more, cursor=cursor, limit=limit)


def is_treedx_page(value: Any) -> bool:
    return isinstance(value, TreeDxPage) or (isinstance(value, dict) and isinstance(value.get("items"), list))


def get_next_cursor(page: TreeDxPage[Any]) -> str | None:
    return page.next_cursor
