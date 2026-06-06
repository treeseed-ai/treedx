defmodule TreeDx.Exec.Backends.ExternalWorker do
  @moduledoc false

  alias TreeDx.Exec.WorkerProtocol

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    with {:ok, url} <- worker_url(),
         body <-
           Jason.encode!(
             WorkerProtocol.request(
               command,
               cwd,
               timeout_ms,
               max_output_bytes,
               opts,
               "external_worker"
             )
           ),
         {:ok, response} <- post(url, body),
         {:ok, result} <- WorkerProtocol.normalize_response(response, "external_worker") do
      {:ok, result}
    end
  end

  defp worker_url do
    case System.get_env("TREEDX_EXEC_WORKER_URL") do
      url when is_binary(url) and url != "" ->
        {:ok, url}

      _ ->
        {:error,
         %{code: "sandbox_unavailable", message: "TREEDX_EXEC_WORKER_URL is not configured."}}
    end
  end

  defp post(url, body) do
    request = {String.to_charlist(url), WorkerProtocol.headers(body), ~c"application/json", body}
    timeout = env_int("TREEDX_EXEC_WORKER_TIMEOUT_MS", 30_000)

    case :httpc.request(:post, request, [timeout: timeout], body_format: :binary) do
      {:ok, {{_, status, _}, _headers, response_body}} when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, _} ->
            {:error,
             %{
               code: "sandbox_unavailable",
               message: "External exec worker returned invalid JSON."
             }}
        end

      {:ok, {{_, 403, _}, _headers, _response_body}} ->
        {:error,
         %{code: "sandbox_policy_denied", message: "External exec worker denied the request."}}

      {:ok, _response} ->
        {:error, %{code: "sandbox_unavailable", message: "External exec worker failed."}}

      {:error, _reason} ->
        {:error, %{code: "sandbox_unavailable", message: "External exec worker was unavailable."}}
    end
  end

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end
end
