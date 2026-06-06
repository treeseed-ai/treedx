from pathlib import Path

import yaml

import treedx_sdk
from treedx_sdk.conformance import TreeDxConformanceAdapter
from treedx_sdk.generated import TREEDX_OPENAPI_OPERATIONS


def test_public_exports() -> None:
    assert treedx_sdk.TreeDxClient is not None
    assert treedx_sdk.TreeDxApiError is not None
    assert TreeDxConformanceAdapter is not None


def test_generated_operations_include_sdk_spec_endpoints() -> None:
    root = Path(__file__).resolve().parents[3]
    endpoints = yaml.safe_load((root / "sdk-spec" / "spec" / "endpoints.yaml").read_text(encoding="utf8"))
    generated = {f"{operation['method']} {operation['path']}" for operation in TREEDX_OPENAPI_OPERATIONS}
    for group_endpoints in (endpoints.get("groups") or {}).values():
        for endpoint in group_endpoints:
            assert endpoint in generated
