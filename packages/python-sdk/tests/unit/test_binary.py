import pytest

from treedx_sdk.binary import assert_binary_body, is_binary_body, to_bytes


def test_binary_helpers_accept_byte_values() -> None:
    assert is_binary_body(b"abc")
    assert is_binary_body(bytearray(b"abc"))
    assert is_binary_body(memoryview(b"abc"))
    assert to_bytes(bytearray(b"abc")) == b"abc"


def test_binary_helpers_reject_strings() -> None:
    with pytest.raises(TypeError):
        assert_binary_body("abc")
