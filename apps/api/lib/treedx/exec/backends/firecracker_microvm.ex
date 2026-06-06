defmodule TreeDx.Exec.Backends.FirecrackerMicrovm do
  @moduledoc false

  alias TreeDx.Exec.WorkerProtocol

  def run(command, cwd, timeout_ms, max_output_bytes, opts \\ %{}) do
    profile = System.get_env("TREEDX_EXEC_MICROVM_PROFILE") || "firecracker"

    opts =
      opts
      |> Map.new()
      |> Map.put("microvmProfile", profile)

    with {:ok, url} <- worker_url(),
         body <-
           Jason.encode!(
             WorkerProtocol.request(
               command,
               cwd,
               timeout_ms,
               max_output_bytes,
               opts,
               "firecracker_or_microvm"
             )
           ),
         {:ok, response} <- post(url, body) do
      WorkerProtocol.normalize_response(response, "firecracker_or_microvm")
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
             %{code: "sandbox_unavailable", message: "MicroVM worker returned invalid JSON."}}
        end

      {:ok, {{_, 403, _}, _headers, _response_body}} ->
        {:error, %{code: "sandbox_policy_denied", message: "MicroVM worker denied the request."}}

      {:ok, _response} ->
        {:error, %{code: "sandbox_unavailable", message: "MicroVM worker failed."}}

      {:error, _reason} ->
        {:error, %{code: "sandbox_unavailable", message: "MicroVM worker was unavailable."}}
    end
  end

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end
end
