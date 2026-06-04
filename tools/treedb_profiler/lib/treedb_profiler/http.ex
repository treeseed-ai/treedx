defmodule TreeDbProfiler.HTTP do
  @moduledoc false

  alias TreeDbProfiler.Timer

  defstruct [:base_url, :token, timeout_ms: 30_000]

  def new(opts) do
    %__MODULE__{
      base_url: String.trim_trailing(opts.base_url, "/"),
      token: opts[:token],
      timeout_ms: opts.timeout_ms
    }
  end

  def request(client, meta, opts \\ []) do
    method = Keyword.fetch!(opts, :method)
    path = Keyword.fetch!(opts, :path)
    json = Keyword.get(opts, :json)
    body = Keyword.get(opts, :body)
    headers = headers(client, Keyword.get(opts, :headers, []), json)
    url = client.base_url <> path
    request_bytes = request_size(json, body)

    {result, started_at, duration_ms} =
      Timer.measure(fn ->
        Req.request(
          method: method,
          url: url,
          headers: headers,
          json: json,
          body: body,
          pool_timeout: client.timeout_ms,
          receive_timeout: client.timeout_ms,
          retry: false
        )
      end)

    {status, response_body, response_bytes, ok, error_code} = normalize_result(result)

    sample = %{
      operation_id: meta.operation_id,
      method: String.upcase(to_string(method)),
      path_template: meta.path_template,
      path: path,
      category: meta.category,
      scenario: meta.scenario,
      fixture: meta.fixture,
      started_at: DateTime.to_iso8601(started_at),
      duration_ms: duration_ms,
      status: status,
      ok: ok,
      error_code: error_code,
      request_bytes: request_bytes,
      response_bytes: response_bytes,
      assertion: :pending
    }

    {sample, response_body}
  end

  defp headers(client, headers, json) do
    auth =
      case client.token do
        nil -> []
        token -> [{"authorization", "Bearer #{token}"}]
      end

    content =
      if is_nil(json), do: [], else: [{"content-type", "application/json"}]

    auth ++ content ++ headers
  end

  defp request_size(nil, nil), do: 0
  defp request_size(json, nil), do: json |> Jason.encode!() |> byte_size()
  defp request_size(nil, body) when is_binary(body), do: byte_size(body)
  defp request_size(_, _), do: 0

  defp normalize_result({:ok, %Req.Response{} = response}) do
    body = response.body
    bytes = response_body_size(body)
    ok = response.status in 200..299
    error_code = error_code(body)
    {response.status, body, bytes, ok, error_code}
  end

  defp normalize_result({:error, error}) do
    {0, %{"error" => %{"code" => "network_error", "message" => Exception.message(error)}}, 0,
     false, "network_error"}
  end

  defp normalize_result({:raised, error, _stack}) do
    {0, %{"error" => %{"code" => "client_error", "message" => Exception.message(error)}}, 0,
     false, "client_error"}
  end

  defp response_body_size(body) when is_binary(body), do: byte_size(body)
  defp response_body_size(body), do: body |> Jason.encode!() |> byte_size()

  defp error_code(%{"error" => %{"code" => code}}), do: code
  defp error_code(_), do: nil
end
