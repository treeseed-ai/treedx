from treedx_sdk.auth import StaticBearerTokenAuthProvider, resolve_authorization_header
from treedx_sdk.config import TreeDxClientConfig


def test_static_bearer_token_provider_returns_token() -> None:
    assert StaticBearerTokenAuthProvider("abc").get_token() == "abc"


def test_authorization_header_format() -> None:
    config = TreeDxClientConfig(base_url="http://treedx.test", token="abc")
    assert resolve_authorization_header(config) == {"Authorization": "Bearer abc"}
