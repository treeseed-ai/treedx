defmodule TreeDx.Graph.Dsl do
  @moduledoc false

  def parse(source) do
    with {:ok, parsed} <- TreeDx.Graph.Native.parse_ctx_dsl(source) do
      {:ok, %{query: parsed["query"], errors: parsed["errors"] || []}}
    end
  end
end
