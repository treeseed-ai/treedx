import os

import pytest

from treedx_sdk import TreeDxClient


def test_live_health_or_clean_skip() -> None:
    base_url = os.environ.get("TREEDX_BASE_URL")
    if not base_url:
        pytest.skip("TREEDX_BASE_URL is not configured")
    client = TreeDxClient(base_url=base_url, token=os.environ.get("TREEDX_TOKEN"))
    assert client.health() is not None
