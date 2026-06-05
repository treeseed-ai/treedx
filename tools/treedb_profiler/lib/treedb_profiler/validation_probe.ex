defmodule TreeDbProfiler.ValidationProbe do
  @moduledoc false

  alias TreeDbProfiler.{HTTP, Hash, ProfileRequest, PublicHygiene}

  def run(_state, %ProfileRequest{validation_probes: []}, _response),
    do: %{samples: [], failures: []}

  def run(%{opts: %{validation_probes: false}}, _request, _response),
    do: %{samples: [], failures: []}

  def run(state, %ProfileRequest{} = request, response) do
    request.validation_probes
    |> Enum.take(state.opts.max_validation_probes_per_request)
    |> Enum.map(&execute_probe(state, request, response, &1))
    |> Enum.reduce(%{samples: [], failures: []}, fn result, acc ->
      %{samples: acc.samples ++ [result.sample], failures: acc.failures ++ result.failures}
    end)
  end

  defp execute_probe(state, request, _response, %{kind: :workspace_file_content_equals}) do
    path =
      "/api/v1/workspaces/#{request.target.workspace_id}/files?path=#{URI.encode_www_form(request.target.path)}"

    {sample, body} = probe_http(state, request, :get, path, nil)

    failures =
      []
      |> validate_hygiene(body)
      |> validate_content(body, request.expectation.content)

    %{sample: mark_probe(sample, failures), failures: failures}
  end

  defp execute_probe(state, request, _response, %{kind: :workspace_file_absent}) do
    path =
      "/api/v1/workspaces/#{request.target.workspace_id}/files?path=#{URI.encode_www_form(request.target.path)}"

    {sample, body} = probe_http(state, request, :get, path, nil)

    failures =
      case {sample.status, get_in(body, ["error", "code"])} do
        {404, _} -> []
        {_, "not_found"} -> []
        _ -> ["expected workspace file #{request.target.path} to be absent"]
      end

    %{sample: mark_probe(sample, failures), failures: failures}
  end

  defp execute_probe(state, request, _response, %{kind: :workspace_status_mentions_path}) do
    path = "/api/v1/workspaces/#{request.target.workspace_id}/status"
    {sample, body} = probe_http(state, request, :get, path, nil)

    failures =
      if contains_value?(body, request.target.path),
        do: [],
        else: ["workspace status missing #{request.target.path}"]

    %{sample: mark_probe(sample, failures), failures: validate_hygiene(body) ++ failures}
  end

  defp execute_probe(state, request, _response, %{kind: :workspace_diff_mentions_path}) do
    path = "/api/v1/workspaces/#{request.target.workspace_id}/diff"
    {sample, body} = probe_http(state, request, :get, path, nil)

    failures =
      if contains_value?(body, request.target.path),
        do: [],
        else: ["workspace diff missing #{request.target.path}"]

    %{sample: mark_probe(sample, failures), failures: validate_hygiene(body) ++ failures}
  end

  defp execute_probe(state, request, _response, %{kind: :blob_download_hash_equals}) do
    path =
      "/api/v1/workspaces/#{request.target.workspace_id}/blobs/download?path=#{URI.encode_www_form(request.target.path)}"

    {sample, body} = probe_http(state, request, :get, path, nil)

    failures =
      if is_binary(body) and Hash.sha256(body) == request.expectation.sha256 do
        []
      else
        ["downloaded blob hash did not match #{request.target.path}"]
      end

    %{sample: mark_probe(sample, failures), failures: failures}
  end

  defp execute_probe(_state, request, _response, probe) do
    sample = %{
      operation_id: "validationProbe",
      method: "INTERNAL",
      path_template: "validation_probe",
      path: "validation_probe",
      category: "validation",
      scenario: "validation",
      fixture: "validation",
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      duration_ms: 0.0,
      status: 0,
      ok: false,
      error_code: "unsupported_probe",
      request_bytes: 0,
      response_bytes: 0,
      assertion: :failed,
      sample_kind: :validation_probe,
      measured_window: :measured,
      counts_toward_primary_rps: false,
      counts_toward_total_http_rps: true,
      parent_request_id: request_id(request)
    }

    %{sample: sample, failures: ["unsupported validation probe #{inspect(probe)}"]}
  end

  defp probe_http(state, request, method, path, body) do
    HTTP.request(
      %{state.client | timeout_ms: state.opts.validation_probe_timeout_ms},
      %{
        operation_id: "#{request.operation_id}.validationProbe",
        path_template: request.path_template,
        category: "validation_probe",
        scenario: state.opts.scenario,
        fixture: state.opts.fixture
      },
      [method: method, path: path]
      |> put_payload(body)
      |> Keyword.put(:sample_kind, :validation_probe)
      |> Keyword.put(:counts_toward_primary_rps, false)
      |> Keyword.put(:counts_toward_total_http_rps, true)
      |> Keyword.put(:parent_request_id, request.id)
    )
  end

  defp request_id(%ProfileRequest{id: id}), do: id
  defp request_id(_), do: nil

  defp put_payload(opts, nil), do: opts
  defp put_payload(opts, body) when is_binary(body), do: Keyword.put(opts, :body, body)
  defp put_payload(opts, body), do: Keyword.put(opts, :json, body)

  defp validate_content(failures, body, expected) do
    content = get_in(body, ["file", "content"]) || body["content"] || body["body"]

    cond do
      not is_binary(expected) ->
        failures

      content == expected ->
        failures

      true ->
        failures ++ ["workspace file content did not match expected SHA #{Hash.sha256(expected)}"]
    end
  end

  defp validate_hygiene(failures, body), do: failures ++ hygiene_failures(body)
  defp validate_hygiene(body), do: hygiene_failures(body)

  defp hygiene_failures(body) do
    case PublicHygiene.validate(body) do
      :ok -> []
      {:error, message} -> [message]
    end
  end

  defp mark_probe(sample, []), do: %{sample | assertion: :passed, ok: true, error_code: nil}

  defp mark_probe(sample, _),
    do: %{sample | assertion: :failed, ok: false, error_code: "validation_probe_failed"}

  defp contains_value?(value, expected) when is_binary(value) and is_binary(expected),
    do: String.contains?(value, expected)

  defp contains_value?(value, expected) when is_map(value),
    do:
      Enum.any?(value, fn {key, val} ->
        contains_value?(key, expected) or contains_value?(val, expected)
      end)

  defp contains_value?(value, expected) when is_list(value),
    do: Enum.any?(value, &contains_value?(&1, expected))

  defp contains_value?(_value, _expected), do: false
end
