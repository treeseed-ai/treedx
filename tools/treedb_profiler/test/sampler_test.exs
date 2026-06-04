defmodule TreeDbProfiler.SamplerTest do
  use ExUnit.Case, async: true

  alias TreeDbProfiler.Sampler

  test "retains all failures and bounded successes" do
    success = sample("readRepositoryFile", true)
    failure = %{sample("writeWorkspaceFile", false) | assertion: :failed, error_code: "conflict"}

    report =
      Sampler.new(1)
      |> Sampler.add(success)
      |> Sampler.add(success)
      |> Sampler.add(failure)
      |> Sampler.report(true)

    assert length(report["failures"]) == 1
    assert length(report["successes"]["readRepositoryFile"]) == 1

    hidden =
      Sampler.new(1)
      |> Sampler.add(success)
      |> Sampler.report(false)

    assert hidden["successes"] == %{}
  end

  defp sample(operation_id, ok?) do
    %{
      operation_id: operation_id,
      method: "GET",
      path_template: "/x",
      path: "/x",
      category: "test",
      duration_ms: 1.0,
      status: if(ok?, do: 200, else: 409),
      ok: ok?,
      error_code: nil,
      request_bytes: 1,
      response_bytes: 1,
      assertion: :passed
    }
  end
end
