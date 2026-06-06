defmodule TreeDx.Graph.RefreshJobs do
  @moduledoc false

  def start(ctx, params, refresh_mode, fallback_reason, stale) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    job_id = job_id(ctx.repo["id"], ctx.ref, now)

    record = %{
      jobId: job_id,
      repoId: ctx.repo["id"],
      refName: ctx.ref,
      requestedPaths: normalize_list(params["paths"], ["**"]),
      changedPaths: normalize_list(params["changedPaths"], []),
      baseGraphVersion: params["baseGraphVersion"],
      graphVersion: nil,
      refreshMode: refresh_mode,
      fallbackReason: fallback_reason,
      stale: stale,
      status: "running",
      startedAt: now,
      completedAt: nil,
      indexedPathCount: 0,
      removedPathCount: 0,
      errorCode: nil
    }

    with {:ok, saved} <- TreeDx.Store.put_graph_refresh_job(record), do: {:ok, saved}
  end

  def complete(job, graph_version, indexed_path_count, removed_path_count) do
    record =
      job
      |> Map.put("status", "completed")
      |> Map.put("graphVersion", graph_version)
      |> Map.put(
        "completedAt",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )
      |> Map.put("indexedPathCount", indexed_path_count)
      |> Map.put("removedPathCount", removed_path_count)

    TreeDx.Store.put_graph_refresh_job(record)
  end

  def fail(job, error_code) do
    record =
      job
      |> Map.put("status", "failed")
      |> Map.put(
        "completedAt",
        DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      )
      |> Map.put("errorCode", error_code)

    TreeDx.Store.put_graph_refresh_job(record)
  end

  def get(repo_id, job_id, params, principal) do
    with {:ok, scope} <-
           TreeDx.Capabilities.require_capability(principal, "graph:query", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDx.Store.get_repository(repo_id),
         ref <- params["ref"] || repo["defaultRef"] || "refs/heads/main",
         :ok <- TreeDx.Capabilities.require_ref(scope, ref),
         {:ok, job} <- TreeDx.Store.get_graph_refresh_job(repo_id, job_id),
         {:ok, job} <- require_job(job) do
      {:ok, %{job: public(job)}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Graph refresh job not found."}}
      other -> other
    end
  end

  def public(job) do
    %{
      jobId: job["jobId"],
      repoId: job["repoId"],
      ref: job["refName"],
      requestedPaths: job["requestedPaths"] || [],
      changedPaths: job["changedPaths"] || [],
      baseGraphVersion: job["baseGraphVersion"],
      graphVersion: job["graphVersion"],
      refreshMode: job["refreshMode"],
      fallbackReason: job["fallbackReason"],
      stale: job["stale"] || false,
      status: job["status"],
      startedAt: job["startedAt"],
      completedAt: job["completedAt"],
      indexedPathCount: job["indexedPathCount"] || 0,
      removedPathCount: job["removedPathCount"] || 0,
      errorCode: job["errorCode"]
    }
  end

  defp require_job(nil),
    do: {:error, %{code: "not_found", message: "Graph refresh job not found."}}

  defp require_job(job), do: {:ok, job}

  defp normalize_list(nil, default), do: default
  defp normalize_list([], default), do: default
  defp normalize_list(list, _default) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_list(value, _default) when is_binary(value), do: [value]

  defp job_id(repo_id, ref, now) do
    hash =
      :crypto.hash(:sha256, "#{repo_id}|#{ref}|#{now}|#{System.unique_integer()}")
      |> Base.encode16(case: :lower)

    "grjob_#{String.slice(hash, 0, 24)}"
  end
end
