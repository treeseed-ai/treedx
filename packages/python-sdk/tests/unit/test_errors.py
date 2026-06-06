from treedx_sdk.errors import TreeDxApiError


def test_error_from_response_preserves_payload() -> None:
    payload = {"error": {"code": "permission_denied", "message": "Denied", "details": {"scope": "repo"}}}
    error = TreeDxApiError.from_response(403, payload)
    assert error.status == 403
    assert error.code == "permission_denied"
    assert error.message == "Denied"
    assert error.details == {"scope": "repo"}
    assert error.payload == payload


def test_network_error_contract() -> None:
    error = TreeDxApiError.network("failed")
    assert error.status == 0
    assert error.code == "network_error"
