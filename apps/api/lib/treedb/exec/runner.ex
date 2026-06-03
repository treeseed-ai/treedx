defmodule TreeDb.Exec.Runner do
  @moduledoc false

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    TreeDb.Exec.Backend.run(command, cwd, timeout_ms, max_output_bytes, opts)
  end
end
