defmodule TreeDxProfiler.Hash do
  @moduledoc false

  def sha256(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  def byte_length(content) when is_binary(content), do: byte_size(content)
end
