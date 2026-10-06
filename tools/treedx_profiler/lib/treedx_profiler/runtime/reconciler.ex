defmodule TreeDxProfiler.Reconciler do
  @moduledoc false

  alias TreeDxProfiler.ModelState

  def final_report(state, model) do
    failures =
      Enum.reject(
        state.assertions || [],
        &(&1.passed || Map.get(&1, :status) == :race_interference)
      )

    model_summary = ModelState.report(model)

    drift =
      failures
      |> Enum.take(100)
      |> Enum.map(fn failure ->
        %{
          "operationId" => failure[:operationId] || failure[:operation_id],
          "requestId" => failure[:requestId] || failure[:request_id],
          "message" => failure[:error] || failure[:message],
          "pathTemplate" => failure[:pathTemplate] || failure[:path_template]
        }
      end)

    %{
      "totalRuns" => if(Map.get(state.opts, :model_reconciliation), do: 1, else: 0),
      "passed" => if(drift == [], do: 1, else: 0),
      "failed" => if(drift == [], do: 0, else: 1),
      "sampleSize" => state.opts.reconciliation_sample_size,
      "model" => model_summary,
      "drift" => %{"total" => length(drift), "samples" => drift}
    }
  end
end
