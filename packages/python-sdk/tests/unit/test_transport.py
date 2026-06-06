import httpx
import pytest

from treedx_sdk.config import TreeDxClientConfig
from treedx_sdk.errors import TreeDxApiError
from treedx_sdk.transport import HttpxTransport, TreeDxRequest


def test_transport_wraps_network_errors() -> None:
    transport = HttpxTransport(TreeDxClientConfig(base_url="http://127.0.0.1:1", timeout=0.001))
    with pytest.raises(TreeDxApiError) as exc:
        transport.request(TreeDxRequest(method="GET", path="/api/v1/health"))
    assert exc.value.code == "network_error"


def test_transport_class_is_importable() -> None:
    assert httpx.Client is not None
