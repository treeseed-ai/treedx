from __future__ import annotations

import sys
from pathlib import Path

from generate_treedx_openapi_types import OUTPUT_PATH, render_openapi_types


def main() -> None:
    expected = render_openapi_types()
    actual = OUTPUT_PATH.read_text(encoding="utf8") if OUTPUT_PATH.exists() else ""
    if actual != expected:
        print("TreeDX generated OpenAPI metadata is stale. Run scripts/generate_treedx_openapi_types.py.", file=sys.stderr)
        raise SystemExit(1)
    print("TreeDX generated OpenAPI metadata is fresh")


if __name__ == "__main__":
    main()
