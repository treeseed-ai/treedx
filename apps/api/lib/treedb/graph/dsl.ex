defmodule TreeDb.Graph.Dsl do
  @moduledoc false

  def parse(source) do
    with {:ok, parsed} <- TreeDb.Graph.Native.parse_ctx_dsl(source) do
      {:ok, %{query: parsed["query"], errors: parsed["errors"] || []}}
    end
  end
end
