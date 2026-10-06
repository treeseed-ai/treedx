defmodule TreeDxProfiler.ProfileRequest do
  @moduledoc false

  @enforce_keys [
    :id,
    :operation_id,
    :operation_type,
    :method,
    :path_template,
    :path,
    :category,
    :expected_status,
    :validation_rule,
    :generated_at,
    :seed
  ]

  defstruct [
    :id,
    :operation_id,
    :operation_type,
    :method,
    :path_template,
    :path,
    :category,
    :body,
    :headers,
    :expected_status,
    :validation_rule,
    :target,
    :expectation,
    :precondition,
    :postconditions,
    :race_context,
    :validation_probes,
    :state_effect_on_status,
    :state_effect,
    :failure_effect,
    :generated_at,
    :seed
  ]

  def new(attrs) do
    attrs =
      attrs
      |> Map.put_new(:headers, [])
      |> Map.put_new(:body, nil)
      |> Map.put_new(:target, %{})
      |> Map.put_new(:expectation, %{})
      |> Map.put_new(:precondition, %{})
      |> Map.put_new(:postconditions, [])
      |> Map.put_new(:race_context, %{})
      |> Map.put_new(:validation_probes, [])
      |> Map.put_new(:state_effect_on_status, %{})
      |> Map.put_new(:state_effect, nil)
      |> Map.put_new(:failure_effect, nil)
      |> Map.put_new(:generated_at, DateTime.utc_now() |> DateTime.to_iso8601())

    struct!(__MODULE__, attrs)
  end

  def to_meta(%__MODULE__{} = request, scenario, fixture) do
    %{
      operation_id: request.operation_id,
      path_template: request.path_template,
      category: request.category,
      scenario: scenario,
      fixture: fixture
    }
  end
end
