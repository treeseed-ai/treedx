defmodule TreeDxSdk.Binary do
  @moduledoc false

  def binary_body?(value) when is_binary(value), do: true
  def binary_body?(value) when is_list(value), do: IO.iodata_to_binary(value) && true
  def binary_body?(_), do: false

  def assert_binary_body!(value) do
    if binary_body?(value), do: :ok, else: raise(ArgumentError, "expected binary or iodata body")
  end

  def to_binary(value) when is_binary(value), do: value
  def to_binary(value) when is_list(value), do: IO.iodata_to_binary(value)
end
