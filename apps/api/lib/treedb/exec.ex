defmodule TreeDb.Exec do
  @moduledoc false

  alias TreeDb.Exec.{Materializer, Policy, Runner}

  @default_timeout_ms 10_000
  @max_timeout_ms 30_000
  @default_output_bytes 60_000
  @max_output_bytes 100_000

  def run(workspace_id, params, principal) do
    mode = normalize_mode(params["mode"] || "read_only")
    command = params["cmd"] || ""
    timeout_ms = params["timeoutMs"] |> coerce_int(@default_timeout_ms) |> min(@max_timeout_ms)

    max_output =
      params["maxOutputBytes"] |> coerce_int(@default_output_bytes) |> min(@max_output_bytes)

    outcome =
      with {:ok, ctx} <- context(workspace_id, principal, capability_for(mode)),
           :ok <- workspace_allows_mode(ctx.workspace, mode),
           :ok <- workspace_ready(ctx.workspace),
           :ok <- Policy.allow(command, mode),
           :ok <- audit_started(ctx, workspace_id, mode, command),
           {:ok, cwd} <- Materializer.materialize(ctx),
           before <- Materializer.snapshot(cwd),
           started <- System.monotonic_time(:millisecond),
           {:ok, result} <- Runner.run(command, cwd, timeout_ms, max_output),
           after_snapshot <- Materializer.snapshot(cwd),
           changed_paths <- Materializer.changed_paths(before, after_snapshot),
           :ok <- enforce_read_only(mode, changed_paths),
           {:ok, persisted_paths} <-
             persist_write_limited(mode, ctx, before, after_snapshot, changed_paths) do
        elapsed_ms = max(System.monotonic_time(:millisecond) - started, 0)
        changed_paths = if mode == "write_limited", do: persisted_paths, else: changed_paths

        TreeDb.Audit.append("exec.completed", %{
          actor_id: actor_id(principal),
          tenant_id: tenant_id(principal),
          repo_id: ctx.repo["id"],
          workspace_id: workspace_id,
          operation: "workspace.exec",
          status: "ok",
          data: %{
            mode: mode,
            command: command,
            commandProfile: Policy.profile(mode),
            exitCode: result.exit_code,
            elapsedMs: elapsed_ms,
            truncated: result.truncated,
            changedPaths: changed_paths
          }
        })

        {:ok,
         %{
           exitCode: result.exit_code,
           stdout: result.stdout,
           stderr: result.stderr,
           elapsedMs: elapsed_ms,
           truncated: result.truncated,
           changedPaths: changed_paths
         }}
      end

    case outcome do
      {:error, error} ->
        TreeDb.Audit.append("exec.rejected", %{
          actor_id: actor_id(principal),
          tenant_id: tenant_id(principal),
          workspace_id: workspace_id,
          operation: "workspace.exec",
          status: "error",
          data: %{mode: mode, command: command, code: error[:code] || error["code"]}
        })

        {:error, error}

      other ->
        other
    end
  end

  defp audit_started(ctx, workspace_id, mode, command) do
    TreeDb.Audit.append("exec.started", %{
      actor_id: actor_id(ctx.principal),
      tenant_id: tenant_id(ctx.principal),
      repo_id: ctx.repo["id"],
      workspace_id: workspace_id,
      operation: "workspace.exec",
      status: "started",
      data: %{mode: mode, command: command, commandProfile: Policy.profile(mode)}
    })

    :ok
  end

  defp context(workspace_id, principal, capability) do
    with {:ok, workspace} when is_map(workspace) <- TreeDb.Store.get_workspace(workspace_id),
         :ok <- same_actor(workspace, principal),
         {:ok, scope} <-
           TreeDb.Capabilities.require_capability(
             principal,
             capability,
             workspace["repositoryId"]
           ),
         :ok <- workspace_has_capability(workspace, capability),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(workspace["repositoryId"]) do
      {:ok, %{workspace: workspace, repo: repo, scope: scope, principal: principal}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      other -> other
    end
  end

  defp workspace_ready(workspace) do
    cond do
      workspace["status"] not in ["ready", "committed"] ->
        {:error, %{code: "conflict", message: "Workspace is not available for exec."}}

      DateTime.compare(parse_time!(workspace["expiresAt"]), DateTime.utc_now()) != :gt ->
        {:error, %{code: "conflict", message: "Workspace has expired."}}

      true ->
        :ok
    end
  end

  defp workspace_allows_mode(workspace, "write_limited") do
    if workspace["mode"] == "writable" and workspace["status"] == "ready" and workspace["leaseId"] do
      :ok
    else
      {:error, %{code: "permission_denied", message: "Workspace is not writable."}}
    end
  end

  defp workspace_allows_mode(_workspace, _mode), do: :ok

  defp workspace_has_capability(workspace, capability) do
    if capability in (workspace["capabilities"] || []) do
      :ok
    else
      {:error,
       %{
         code: "permission_denied",
         message: "Permission denied.",
         details: %{capability: capability}
       }}
    end
  end

  defp same_actor(workspace, principal) do
    if workspace["actorId"] == actor_id(principal) do
      :ok
    else
      {:error, %{code: "permission_denied", message: "Permission denied."}}
    end
  end

  defp enforce_read_only("read_only", []), do: :ok

  defp enforce_read_only("read_only", changed_paths),
    do:
      {:error,
       %{
         code: "permission_denied",
         message: "Read-only exec changed files.",
         details: %{changedPaths: changed_paths}
       }}

  defp enforce_read_only(_mode, _changed_paths), do: :ok

  defp persist_write_limited("write_limited", ctx, before, after_snapshot, changed_paths) do
    changed_paths
    |> Enum.map(&persist_change(ctx, before, after_snapshot, &1))
    |> collect_ok()
  end

  defp persist_write_limited(_mode, _ctx, _before, _after_snapshot, changed_paths),
    do: {:ok, changed_paths}

  defp persist_change(ctx, before, after_snapshot, path) do
    with :ok <- TreeDb.Files.PathPolicy.authorize(ctx.workspace, path, false) do
      cond do
        Map.has_key?(after_snapshot, path) ->
          content = File.read!(after_snapshot[path].absolute)

          if String.valid?(content) do
            TreeDb.Store.put_workspace_file(%{
              workspaceId: ctx.workspace["id"],
              path: path,
              op: "put",
              encoding: "utf8",
              contentBase64: Base.encode64(content),
              expectedSha: nil,
              baseSha: nil
            })
            |> case do
              {:ok, _record} -> {:ok, path}
              other -> other
            end
          else
            {:error,
             %{
               code: "unsupported_media_type",
               message: "Changed file is not valid UTF-8.",
               details: %{path: path}
             }}
          end

        Map.has_key?(before, path) ->
          TreeDb.Store.put_workspace_file(%{
            workspaceId: ctx.workspace["id"],
            path: path,
            op: "delete",
            expectedSha: nil,
            baseSha: nil
          })
          |> case do
            {:ok, _record} -> {:ok, path}
            other -> other
          end

        true ->
          {:ok, path}
      end
    end
  end

  defp collect_ok(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {:ok, path}, {:ok, acc} -> {:cont, {:ok, [path | acc]}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp normalize_mode("verification"), do: "verification"
  defp normalize_mode("write_limited"), do: "write_limited"
  defp normalize_mode("read_only"), do: "read_only"
  defp normalize_mode("read-only"), do: "read_only"
  defp normalize_mode(_), do: "read_only"

  defp capability_for("verification"), do: "workspace:exec:verification"
  defp capability_for("write_limited"), do: "workspace:exec:write_limited"
  defp capability_for(_), do: "workspace:exec:read_only"

  defp coerce_int(value, _default) when is_integer(value), do: value

  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> default
    end
  end

  defp coerce_int(_value, default), do: default

  defp parse_time!(value) do
    {:ok, datetime, _} = DateTime.from_iso8601(value)
    datetime
  end

  defp actor_id(principal),
    do: principal["actorId"] || principal[:actorId] || principal[:actor_id]

  defp tenant_id(principal),
    do: principal["tenantId"] || principal[:tenantId] || principal[:tenant_id]
end
