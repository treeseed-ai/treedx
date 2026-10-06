defmodule TreeDxProfiler.ScenarioHttp do
  @moduledoc false

  alias TreeDxProfiler.{
    EndpointMatrix,
    HTTP,
    OpenApiResponseValidator,
    ProbePolicy,
    ProfileRequest,
    ReplayLog,
    Validation,
    ValidationProbe
  }

  def call!(state, method, path, operation_id, category, body, assertion_fun, opts \\ []) do
    {state, _body} =
      call(state, method, path, operation_id, category, body,
        expected: Keyword.get(opts, :expected, 200),
        assert: assertion_fun,
        measured?: Keyword.get(opts, :measured?, true),
        headers: Keyword.get(opts, :headers, [])
      )

    state
  end

  def call(state, method, path, operation_id, category, body, opts) do
    meta = %{
      operation_id: operation_id,
      path_template: template(path),
      category: category,
      scenario: state.opts.scenario,
      fixture: state.opts.fixture
    }

    req_opts =
      [method: method, path: path, headers: Keyword.get(opts, :headers, [])]
      |> put_payload(body)

    {sample, response} = HTTP.request(state.client, meta, req_opts)
    expected = List.wrap(Keyword.get(opts, :expected, 200))
    assertion_fun = Keyword.get(opts, :assert, &assert_ok/1)
    {assertion, assertion_error} = run_assertion(sample, response, expected, assertion_fun)
    openapi = openapi_result(state.opts, operation_id, sample, response)
    {assertion, assertion_error} = merge_openapi_assertion(assertion, assertion_error, openapi)

    sample =
      if assertion == :passed do
        %{sample | assertion: assertion, ok: true, error_code: nil}
      else
        %{
          sample
          | assertion: assertion,
            ok: false,
            error_code: sample.error_code || "assertion_failed"
        }
      end

    state =
      if Keyword.get(opts, :measured?, true) do
        update_in(state.samples, &(&1 ++ [sample]))
      else
        state
      end

    assertion_record = %{
      operationId: operation_id,
      path: path,
      pathTemplate: meta.path_template,
      fixture: state.opts.fixture,
      size: state.opts.size,
      rule: get_in(EndpointMatrix.operation_map(), [operation_id, "validation", "rule"]),
      openapiValidation: openapi,
      passed: assertion == :passed,
      error: assertion_error
    }

    ReplayLog.record(
      state.opts,
      %{
        id: nil,
        operation_id: operation_id,
        worker_id: nil,
        seed: state.opts.seed,
        expected_status: expected,
        body: body,
        precondition: %{}
      },
      sample,
      assertion_record
    )

    if assertion == :failed and state.opts.fail_fast do
      raise "profiler assertion failed for #{operation_id}: #{assertion_error}"
    end

    {update_in(state.assertions, &(&1 ++ [assertion_record])), response}
  end

  def execute_profile_request(state, %ProfileRequest{} = request) do
    req_opts =
      [method: request.method, path: request.path, headers: request.headers || []]
      |> put_payload(request.body)

    {sample, response} =
      HTTP.request(
        state.client,
        ProfileRequest.to_meta(request, state.opts.scenario, state.opts.fixture),
        req_opts
      )

    {assertion, assertion_error, probe_samples, probe_failures} =
      run_profile_assertion(state, request, sample, response)

    openapi = openapi_result(state.opts, request.operation_id, sample, response)
    {assertion, assertion_error} = merge_openapi_assertion(assertion, assertion_error, openapi)

    sample =
      if assertion == :passed do
        %{
          sample
          | assertion: assertion,
            ok: true,
            error_code: nil
        }
      else
        %{
          sample
          | assertion: assertion,
            ok: false,
            error_code: sample.error_code || "assertion_failed"
        }
      end

    assertion_record = %{
      operationId: request.operation_id,
      requestId: request.id,
      path: request.path,
      pathTemplate: request.path_template,
      fixture: state.opts.fixture,
      size: state.opts.size,
      rule: request.validation_rule,
      semantic: state.opts.semantic_validation,
      validationProbes: length(probe_samples),
      validationProbeSamples: maybe_retain_probe_samples(state.opts, probe_samples),
      openapiValidation: openapi,
      passed: assertion == :passed,
      error: assertion_error
    }

    sample =
      if probe_failures == [] do
        sample
      else
        %{sample | assertion: :failed, ok: false, error_code: "validation_probe_failed"}
      end

    assertion_record =
      if probe_failures == [] do
        assertion_record
      else
        %{assertion_record | passed: false, error: Enum.join(probe_failures, "; ")}
      end

    if assertion_record.passed == false and state.opts.fail_fast do
      raise "profiler assertion failed for #{request.operation_id}: #{assertion_record.error}"
    end

    ReplayLog.record(state.opts, request, sample, replay_assertion_record(assertion_record))

    {sample, response, assertion_record}
  end

  defp openapi_result(opts, operation_id, sample, response) do
    case OpenApiResponseValidator.validate_response(operation_id, sample.status, response,
           enabled: opts.openapi_response_validation
         ) do
      :ok ->
        %{operationId: operation_id, status: sample.status, passed: true, message: nil}

      {:error, message} ->
        %{operationId: operation_id, status: sample.status, passed: false, message: message}
    end
  end

  defp merge_openapi_assertion(:passed, nil, %{passed: false, message: message}),
    do: {:failed, "OpenAPI response validation failed: #{message}"}

  defp merge_openapi_assertion(assertion, assertion_error, _openapi),
    do: {assertion, assertion_error}

  defp run_profile_assertion(state, request, sample, response) do
    cond do
      sample.status not in List.wrap(request.expected_status) ->
        {:failed, "expected status #{inspect(request.expected_status)}, got #{sample.status}", [],
         []}

      sample.status not in 200..299 ->
        {:failed, "non-success status #{sample.status} requires race classification", [], []}

      not state.opts.semantic_validation ->
        run_legacy_profile_assertion(response, request.validation_rule)

      true ->
        ctx = %{sample: sample, response: response, state: state, request: request}

        case Validation.validate(request.validation_rule, ctx) do
          :ok ->
            probes =
              if ProbePolicy.run_success_probes?(state.opts, request),
                do: ValidationProbe.run(state, request, response),
                else: %{samples: [], failures: []}

            if probes.failures == [] do
              {:passed, nil, probes.samples, []}
            else
              {:failed, Enum.join(probes.failures, "; "), probes.samples, probes.failures}
            end

          {:error, message} ->
            probes =
              if ProbePolicy.run_failure_probes?(state.opts, request),
                do: ValidationProbe.run(state, request, response),
                else: %{samples: [], failures: []}

            {:failed, message, probes.samples, probes.failures}
        end
    end
  end

  defp maybe_retain_probe_samples(_opts, probe_samples), do: probe_samples

  defp replay_assertion_record(%{validationProbeSamples: _} = assertion_record),
    do: Map.delete(assertion_record, :validationProbeSamples)

  defp replay_assertion_record(assertion_record), do: assertion_record

  defp run_legacy_profile_assertion(response, rule) do
    assertion_fun = assertion_for_rule(rule)

    try do
      assertion_fun.(response)
      {:passed, nil, [], []}
    rescue
      error -> {:failed, Exception.message(error), [], []}
    end
  end

  defp assertion_for_rule("search_hits_expected_terms"), do: &assert_search_hits/1
  defp assertion_for_rule("query_hits_expected_terms"), do: &assert_ok/1
  defp assertion_for_rule("graph_query_has_expected_shape"), do: &assert_ok/1
  defp assertion_for_rule("context_within_budget"), do: &assert_ok/1
  defp assertion_for_rule("snapshot_has_checksum"), do: &assert_ok/1
  defp assertion_for_rule("artifact_has_metadata"), do: &assert_ok/1
  defp assertion_for_rule(_), do: &assert_ok/1

  defp put_payload(opts, nil), do: opts
  defp put_payload(opts, body) when is_binary(body), do: Keyword.put(opts, :body, body)
  defp put_payload(opts, body), do: Keyword.put(opts, :json, body)

  defp run_assertion(sample, response, expected, assertion_fun) do
    cond do
      sample.status not in expected ->
        {:failed, "expected status #{inspect(expected)}, got #{sample.status}"}

      true ->
        try do
          assertion_fun.(response)
          {:passed, nil}
        rescue
          error -> {:failed, Exception.message(error)}
        end
    end
  end

  defp template(path) do
    path
    |> String.replace(~r/repo_[A-Za-z0-9_-]+/, "{repo_id}")
    |> String.replace(~r/ws_[A-Za-z0-9_-]+/, "{workspace_id}")
    |> String.replace(~r/snap_[A-Za-z0-9_-]+/, "{snapshot_id}")
    |> String.replace(~r/artifact_[A-Za-z0-9_-]+/, "{artifact_id}")
    |> String.replace(~r/\?.*$/, "")
  end

  def assert_ok(%{"ok" => true}), do: :ok
  def assert_ok(%{"status" => "ok"}), do: :ok
  def assert_ok(_payload), do: raise("expected ok response")

  def assert_ok_or_unavailable(%{"ok" => false, "error" => %{"code" => "service_unavailable"}}),
    do: :ok

  def assert_ok_or_unavailable(payload), do: assert_ok(payload)

  def assert_ok_or_not_found(%{"ok" => false, "error" => %{"code" => "not_found"}}), do: :ok
  def assert_ok_or_not_found(payload), do: assert_ok(payload)

  def assert_ok_or_forbidden(%{"ok" => false, "error" => %{"code" => "permission_denied"}}),
    do: :ok

  def assert_ok_or_forbidden(payload), do: assert_ok(payload)

  def assert_ok_or_validation(%{"ok" => false, "error" => %{"code" => "validation_error"}}),
    do: :ok

  def assert_ok_or_validation(payload), do: assert_ok(payload)

  def assert_ok_or_expected_error(%{"ok" => false, "error" => %{"code" => code}})
      when code in [
             "conflict",
             "validation_error",
             "permission_denied",
             "unsupported_transport",
             "sandbox_unavailable",
             "sandbox_policy_denied",
             "not_found"
           ],
      do: :ok

  def assert_ok_or_expected_error(payload), do: assert_ok(payload)

  def assert_binary_or_ok(binary) when is_binary(binary), do: :ok
  def assert_binary_or_ok(payload), do: assert_ok(payload)

  def assert_search_hits(payload) do
    assert_ok(payload)
    results = payload["results"] || get_in(payload, ["search", "results"]) || []
    if length(results) <= 0, do: raise("expected search results")
  end

  def assert_path(payload, path) do
    assert_ok(payload)
    actual = get_in(payload, ["file", "path"]) || get_in(payload, ["blob", "path"])
    if actual != path, do: raise("expected path #{path}, got #{inspect(actual)}")
  end

  def assert_truthy(nil, label), do: raise("expected #{label}")
  def assert_truthy("", label), do: raise("expected #{label}")
  def assert_truthy(_, _), do: :ok
end
