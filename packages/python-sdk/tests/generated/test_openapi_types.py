from treedx.generated import TREEDX_OPENAPI_OPERATION_COUNT, TREEDX_OPENAPI_OPERATIONS


def test_openapi_operation_count() -> None:
    assert TREEDX_OPENAPI_OPERATION_COUNT == 120
    assert len(TREEDX_OPENAPI_OPERATIONS) == 120
