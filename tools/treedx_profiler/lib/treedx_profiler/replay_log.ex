defmodule TreeDxProfiler.ReplayLog do
  @moduledoc false

  alias TreeDxProfiler.Hash

  def record(opts, request, sample, assertion) do
    if Map.get(opts, :request_ledger, true) and opts.replay_log do
      append(opts.replay_log, entry(request, sample, assertion))
    end

    if assertion[:passed] == false and opts.failure_replay_log do
      append(opts.failure_replay_log, entry(request, sample, assertion))
    end

    :ok
  end

  def report(opts) do
    %{
      "requestLedger" => Map.get(opts, :request_ledger, true),
      "replayLog" => opts.replay_log,
      "failureReplayLog" => opts.failure_replay_log
    }
  end

  defp append(path, entry) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(entry) <> "\n", [:append])
  end

  defp entry(request, sample, assertion) do
    %{
      "requestId" => request_id(request),
      "workerId" => Map.get(request || %{}, :worker_id),
      "operationId" => operation_id(request, sample),
      "seed" => Map.get(request || %{}, :seed),
      "method" => sample.method,
      "pathTemplate" => sample.path_template,
      "path" => sample.path,
      "bodyHash" => body_hash(request),
      "expectedStatus" => expected_status(request),
      "precondition" => sanitize(Map.get(request || %{}, :precondition, %{})),
      "result" => %{
        "status" => sample.status,
        "ok" => sample.ok,
        "errorCode" => sample.error_code,
        "durationMs" => sample.duration_ms
      },
      "assertion" => sanitize(assertion)
    }
  end

  defp request_id(nil), do: nil
  defp request_id(request), do: Map.get(request, :id)
  defp operation_id(nil, sample), do: sample.operation_id
  defp operation_id(request, _sample), do: Map.get(request, :operation_id)
  defp expected_status(nil), do: nil
  defp expected_status(request), do: Map.get(request, :expected_status)

  defp body_hash(nil), do: nil

  defp body_hash(request) do
    body = Map.get(request, :body)

    cond do
      is_nil(body) -> nil
      is_binary(body) -> Hash.sha256(body)
      true -> body |> Jason.encode!() |> Hash.sha256()
    end
  end

  defp sanitize(value) do
    value
    |> Jason.encode!()
    |> TreeDxProfiler.PublicHygiene.scrub()
    |> Jason.decode!()
  rescue
    _ -> %{}
  end
end
