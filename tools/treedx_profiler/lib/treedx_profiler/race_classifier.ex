defmodule TreeDxProfiler.RaceClassifier do
  @moduledoc false

  def classify(%{request: request, sample: sample, validation_error: error} = ctx) do
    cond do
      sample.status in acceptable_statuses(request) ->
        classify_acceptable_status(ctx)

      is_binary(error) and state_changed?(ctx) ->
        {:race, race_record(ctx, "state_changed_during_validation")}

      true ->
        {:ok, :not_race}
    end
  end

  def apply_policy({:race, race}, "fail"), do: {:failed, Map.put(race, :countedAs, "failed")}
  def apply_policy({:race, race}, "success"), do: {:passed, Map.put(race, :countedAs, "success")}
  def apply_policy({:race, race}, _), do: {:race, Map.put(race, :countedAs, "race_interference")}
  def apply_policy(other, _), do: other

  defp classify_acceptable_status(ctx) do
    if state_changed?(ctx) or causal_request_id(ctx) do
      {:race, race_record(ctx, likely_cause(ctx))}
    else
      {:ok, :not_race}
    end
  end

  defp acceptable_statuses(request) do
    request.race_context
    |> Map.get(:acceptable_statuses, Map.get(request.race_context, "acceptableStatuses", []))
    |> Enum.map(fn
      status when is_integer(status) -> status
      status when is_binary(status) -> String.to_integer(status)
    end)
  end

  defp state_changed?(%{precondition: pre, current_state: current}) do
    pre != %{} and current != %{} and pre != current
  end

  defp likely_cause(%{request: request, sample: sample, precondition: pre, current_state: current}) do
    cond do
      sample.status == 404 and Map.get(pre, :workspace_open?) and
          not Map.get(current, :workspace_open?, true) ->
        "workspace_closed_by_another_worker"

      sample.status == 409 and
          Map.get(pre, :workspace_generation) != Map.get(current, :workspace_generation) ->
        "workspace_changed_by_another_worker"

      sample.status == 404 and Map.get(pre, :repo_deleted?) == false and
          Map.get(current, :repo_deleted?) == true ->
        "repo_deleted_by_another_worker"

      request.category == "artifact" and sample.status == 404 ->
        "artifact_changed_by_another_worker"

      true ->
        "concurrent_state_interference"
    end
  end

  defp race_record(ctx, cause) do
    causal_request_id = causal_request_id(ctx)

    %{
      classification: "race_interference",
      operationId: ctx.request.operation_id,
      requestId: ctx.request.id,
      workerId: Map.get(ctx, :worker_id),
      causalRequestId: causal_request_id,
      causalOperationId: nil,
      causalWorkerId: nil,
      targetGenerationBefore:
        Map.get(ctx.precondition || %{}, :workspace_generation) ||
          Map.get(ctx.precondition || %{}, :repo_generation),
      targetGenerationAfter:
        Map.get(ctx.current_state || %{}, :workspace_generation) ||
          Map.get(ctx.current_state || %{}, :repo_generation),
      raceVerified: not is_nil(causal_request_id) or state_changed?(ctx),
      status: ctx.sample.status,
      errorCode: ctx.sample.error_code,
      target: stringify_target(ctx.request.target),
      precondition: stringify_keys(ctx.precondition || %{}),
      observedState: stringify_keys(ctx.current_state || %{}),
      likelyCause: cause,
      countedAs: "race_interference"
    }
  end

  defp causal_request_id(ctx) do
    Map.get(ctx.current_state || %{}, :workspace_last_mutation_request_id) ||
      Map.get(ctx.current_state || %{}, :workspace_closed_by_request_id) ||
      Map.get(ctx.current_state || %{}, :repo_last_request_id)
  end

  defp stringify_target(target), do: stringify_keys(target || %{})

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {camelize(k), v} end)
    |> Map.new()
  end

  defp camelize(key) do
    key
    |> to_string()
    |> String.trim_trailing("?")
    |> Macro.camelize()
    |> then(fn <<first::binary-size(1), rest::binary>> -> String.downcase(first) <> rest end)
  end
end
