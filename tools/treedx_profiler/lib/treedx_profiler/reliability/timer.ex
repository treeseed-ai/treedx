defmodule TreeDxProfiler.Timer do
  @moduledoc false

  def measure(fun) when is_function(fun, 0) do
    started_at = DateTime.utc_now()
    started = System.monotonic_time(:microsecond)

    try do
      result = fun.()
      duration = System.monotonic_time(:microsecond) - started
      {result, started_at, duration / 1000.0}
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - started
        {{:raised, error, __STACKTRACE__}, started_at, duration / 1000.0}
    end
  end
end
