defmodule TreeDx.Exec.WorkerProtocol do
  @moduledoc false

  def request(command, _cwd, timeout_ms, max_output_bytes, opts, backend) do
    %{
      workspaceId: opts["workspaceId"] || opts[:workspace_id],
      actorId: opts["actorId"] || opts[:actor_id],
      mode: opts["mode"] || "read_only",
      cmd: command,
      timeoutMs: timeout_ms,
      maxOutputBytes: max_output_bytes,
      network: opts["network"] || "none",
      resourceLimits: TreeDx.Exec.Backend.resource_limits(opts),
      allowedPaths: opts["allowedPaths"] || opts[:allowed_paths] || [],
      mounts: [%{source: "workspace", path: "workspace", access: "scoped"}],
      cwd: "workspace",
      backend: backend
    }
  end

  def normalize_response(%{"ok" => true} = body, backend) do
    stdout = body["stdout"] || ""
    stderr = body["stderr"] || ""

    {:ok,
     %{
       exit_code: body["exitCode"] || 0,
       stdout: stdout,
       stderr: stderr,
       truncated: body["truncated"] || false,
       sandbox:
         Map.merge(
           %{
             backend: backend,
             isolated: true
           },
           body["sandbox"] || %{}
         ),
       changed_files: body["changedFiles"] || []
     }}
  end

  def normalize_response(%{"error" => %{"code" => code} = error}, _backend) do
    {:error,
     %{
       code: code,
       message: error["message"] || "External exec worker rejected the request."
     }}
  end

  def normalize_response(_body, _backend),
    do:
      {:error,
       %{
         code: "sandbox_unavailable",
         message: "External exec worker returned an invalid response."
       }}

  def headers(body) do
    headers = [{"content-type", "application/json"}]

    headers =
      case System.get_env("TREEDX_EXEC_WORKER_TOKEN") do
        token when is_binary(token) and token != "" ->
          [{"authorization", "Bearer #{token}"} | headers]

        _ ->
          headers
      end

    case System.get_env("TREEDX_EXEC_WORKER_HMAC_SECRET") do
      secret when is_binary(secret) and secret != "" ->
        signature = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
        [{"x-treedx-worker-signature", "sha256=#{signature}"} | headers]

      _ ->
        headers
    end
  end
end
