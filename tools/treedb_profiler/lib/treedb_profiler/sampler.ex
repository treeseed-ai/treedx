defmodule TreeDbProfiler.Sampler do
  @moduledoc false

  def new(limit) do
    %{limit: max(limit, 0), successes: %{}, failures: []}
  end

  def add(sampler, sample) do
    sanitized = sanitize(sample)

    if sample.ok == true and sample.assertion == :passed do
      update_in(sampler.successes, fn successes ->
        Map.update(successes, sample.operation_id, [sanitized], fn existing ->
          existing
          |> then(&if(length(&1) < sampler.limit, do: [sanitized | &1], else: &1))
        end)
      end)
    else
      update_in(sampler.failures, &[sanitized | &1])
    end
  end

  def report(sampler, include_successes?) do
    %{
      "failures" => Enum.reverse(sampler.failures),
      "successes" =>
        if include_successes? do
          sampler.successes
          |> Enum.map(fn {operation, samples} -> {operation, Enum.reverse(samples)} end)
          |> Map.new()
        else
          %{}
        end
    }
  end

  defp sanitize(sample) do
    %{
      "operationId" => sample.operation_id,
      "method" => sample.method,
      "pathTemplate" => sample.path_template,
      "category" => sample.category,
      "durationMs" => sample.duration_ms,
      "status" => sample.status,
      "ok" => sample.ok,
      "errorCode" => sample.error_code,
      "requestBytes" => sample.request_bytes,
      "responseBytes" => sample.response_bytes,
      "assertion" => to_string(sample.assertion)
    }
  end
end
