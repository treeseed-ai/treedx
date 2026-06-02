defmodule TreeDb.Federation do
  @moduledoc false

  def plan_query(params, principal) do
    requested = %{
      repoIds: params["repoIds"] || [],
      refs: params["refs"] || %{},
      paths: params["paths"] || %{},
      queryType: params["queryType"] || "text",
      capabilities: params["capabilities"] || ["files:search"]
    }

    TreeDb.Audit.append("federated.query.started", %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      status: "started",
      operation: "federation.query.plan",
      requested_scope: requested
    })

    {allowed, rejected} =
      requested.repoIds
      |> Enum.map(
        &effective_repo_scope(
          &1,
          requested.refs[&1],
          requested.paths[&1],
          principal,
          requested.capabilities
        )
      )
      |> Enum.reduce({[], []}, fn
        {:ok, scope}, {allowed, rejected} -> {[scope | allowed], rejected}
        {:error, entry}, {allowed, rejected} -> {allowed, [entry | rejected]}
      end)

    payload = %{
      requestedScope: requested,
      effectiveScope: %{repos: Enum.reverse(allowed)},
      rejected: Enum.reverse(rejected),
      executable: false,
      reason: "planner_only_phase_8"
    }

    TreeDb.Audit.append(
      if(rejected == [], do: "federated.query.completed", else: "federated.query.rejected"),
      %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        status: if(rejected == [], do: "ok", else: "partial"),
        operation: "federation.query.plan",
        requested_scope: requested,
        effective_scope: payload.effectiveScope,
        data: %{rejectedCount: length(rejected), allowedCount: length(allowed)}
      }
    )

    {:ok, payload}
  end

  def effective_repo_scope(
        repo_id,
        requested_ref,
        requested_paths,
        principal,
        required_capabilities
      ) do
    ref = requested_ref || "refs/heads/main"
    paths = normalize_paths(requested_paths)

    with {:ok, scope} <-
           TreeDb.Capabilities.require_all(principal, required_capabilities, repo_id),
         :ok <- TreeDb.Capabilities.require_ref(scope, ref),
         allowed_paths <- Enum.filter(paths, &TreeDb.Capabilities.allowed_path?(scope, &1)),
         true <- allowed_paths != [],
         {:ok, placement} when is_map(placement) <- TreeDb.Registry.placement(repo_id) do
      {:ok,
       %{
         repoId: repo_id,
         ref: ref,
         paths: allowed_paths,
         nodeId: placement["primaryNodeId"],
         placement: placement,
         capabilities: required_capabilities
       }}
    else
      false ->
        {:error, %{repoId: repo_id, code: "permission_denied"}}

      {:ok, nil} ->
        {:error, %{repoId: repo_id, code: "not_found"}}

      {:error, error} ->
        {:error, %{repoId: repo_id, code: error[:code] || error["code"] || "permission_denied"}}
    end
  end

  defp normalize_paths(nil), do: ["**"]
  defp normalize_paths([]), do: ["**"]
  defp normalize_paths(paths) when is_list(paths), do: paths
  defp normalize_paths(path) when is_binary(path), do: [path]
end
