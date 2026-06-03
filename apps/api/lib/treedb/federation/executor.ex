defmodule TreeDb.Federation.Executor do
  @moduledoc false

  alias TreeDb.Federation.Merge

  def execute(operation, params, principal, auth_header \\ nil) do
    with {:ok, plan} <- TreeDb.Federation.plan(params, principal, plan_opts(operation, params)),
         :ok <- require_non_empty_scope(plan) do
      audit("#{event_prefix(operation)}.started", principal, plan, [], params)

      {successes, errors} =
        plan.effectiveScope.repos
        |> Enum.map(&execute_repo(operation, &1, params, principal, auth_header))
        |> Enum.reduce({[], []}, fn
          {:ok, success}, {successes, errors} -> {[success | successes], errors}
          {:error, error}, {successes, errors} -> {successes, [error | errors]}
        end)

      successes = Enum.reverse(successes)
      errors = Enum.reverse(errors)

      if errors != [] and !include_errors?(params) do
        audit("#{event_prefix(operation)}.partial", principal, plan, errors, params)

        {:error,
         %{
           code: "federated_partial_failure",
           message: "Federated request failed.",
           details: %{partialFailureCount: length(errors)}
         }}
      else
        with {:ok, payload} <- Merge.merge(operation, successes, plan, params, errors) do
          audit(
            if(errors == [],
              do: "#{event_prefix(operation)}.completed",
              else: "#{event_prefix(operation)}.partial"
            ),
            principal,
            plan,
            errors,
            params
          )

          {:ok, payload}
        end
      end
    end
  end

  defp execute_repo(operation, allowed, params, principal, auth_header) do
    case allowed.source do
      "local" -> execute_local(operation, allowed, params, principal)
      "remote" -> execute_remote(operation, allowed, params, auth_header)
    end
  end

  defp execute_local(operation, allowed, params, principal) do
    local_params = local_params(allowed, params, operation)

    result =
      case operation do
        :search -> TreeDb.RepositoryQuery.search(allowed.repoId, local_params, principal)
        :query -> TreeDb.RepositoryQuery.query(allowed.repoId, local_params, principal)
        :context -> TreeDb.Graph.build_context(allowed.repoId, local_params, principal)
        :graph -> TreeDb.Graph.query(allowed.repoId, local_params, principal)
      end

    case result do
      {:ok, payload} ->
        {:ok, success(allowed, payload)}

      {:error, error} ->
        {:error,
         error_for_allowed(allowed, error[:code] || error["code"] || "federated_node_unavailable")}
    end
  end

  defp execute_remote(operation, allowed, params, auth_header) do
    if is_binary(allowed.baseUrl) and allowed.baseUrl != "" do
      remote_module =
        Application.get_env(:treedb, :federation_remote_node, TreeDb.Federation.RemoteNode)

      case remote_module.execute(operation, allowed, params, auth_header) do
        {:ok, payload} -> {:ok, success(allowed, payload)}
        {:error, error} -> {:error, error}
      end
    else
      {:error,
       %{
         repoId: allowed.repoId,
         nodeId: allowed.nodeId,
         code: "federated_route_not_configured",
         message: "Federated route is not configured.",
         source: "remote"
       }}
    end
  end

  defp local_params(allowed, params, operation) do
    params
    |> Map.take([
      "query",
      "type",
      "filters",
      "sort",
      "options",
      "budget",
      "seedIds",
      "seeds",
      "relations",
      "scopePaths",
      "allowProtected",
      "baseRef"
    ])
    |> Map.put("ref", allowed.ref)
    |> Map.put("paths", allowed.paths)
    |> Map.put("limit", per_repo_limit(params))
    |> Map.put_new("type", if(operation == :query, do: params["type"] || "text", else: nil))
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp success(allowed, payload) do
    %{
      repoId: allowed.repoId,
      ref: allowed.ref,
      nodeId: allowed.nodeId,
      source: allowed.source,
      payload: payload
    }
  end

  defp error_for_allowed(allowed, code) do
    %{
      repoId: allowed.repoId,
      nodeId: allowed.nodeId,
      code: code,
      message: "Federated node was unavailable.",
      source: allowed.source
    }
  end

  defp require_non_empty_scope(%{effectiveScope: %{repos: []}}),
    do:
      {:error,
       %{
         code: "federated_scope_empty",
         message: "No requested repositories are authorized for federation."
       }}

  defp require_non_empty_scope(_), do: :ok

  defp plan_opts(:search, _params),
    do: %{operation: :search, required_capabilities: ["files:search"], executable: true}

  defp plan_opts(:query, params),
    do: %{
      operation: :query,
      required_capabilities: [query_capability(params["type"] || "text")],
      executable: true
    }

  defp plan_opts(:context, _params),
    do: %{operation: :context, required_capabilities: ["graph:query"], executable: true}

  defp plan_opts(:graph, _params),
    do: %{operation: :graph, required_capabilities: ["graph:query"], executable: true}

  defp query_capability(type) when type in ["text", "combined"], do: "files:search"
  defp query_capability("changed_path"), do: "git:diff"
  defp query_capability(_), do: "files:read"

  defp per_repo_limit(params), do: min((params["limit"] || 20) * 2, 100)
  defp include_errors?(params), do: params["includeErrors"] in [true, "true", "1", 1]
  defp event_prefix(:search), do: "federated.search"
  defp event_prefix(:query), do: "federated.query"
  defp event_prefix(:context), do: "federated.context"
  defp event_prefix(:graph), do: "federated.graph"

  defp audit(event, principal, plan, errors, params) do
    TreeDb.Audit.append(event, %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      status: if(errors == [], do: "ok", else: "partial"),
      operation: event,
      requested_scope: %{
        repoCount: length(plan.requestedScope.repoIds),
        timeoutMs: params["timeoutMs"]
      },
      effective_scope: %{repoIds: Enum.map(plan.effectiveScope.repos, & &1.repoId)},
      data: %{
        requestedRepoCount: length(plan.requestedScope.repoIds),
        effectiveRepoCount: length(plan.effectiveScope.repos),
        rejectedRepoCount: length(plan.rejected),
        partialFailureCount: length(errors),
        routes:
          Enum.map(plan.effectiveScope.repos, fn repo ->
            %{repoId: repo.repoId, nodeId: repo.nodeId, source: repo.source}
          end)
      }
    })
  end
end
