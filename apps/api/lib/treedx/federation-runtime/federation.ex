defmodule TreeDx.Federation do
  @moduledoc false

  @default_max_repos 25

  def plan_query(params, principal) do
    capabilities = params["capabilities"] || ["files:search"]

    with {:ok, payload} <-
           plan(params, principal, %{
             operation: :query,
             required_capabilities: capabilities,
             executable: false,
             reason: "planner_only_mvp"
           }) do
      requested = payload.requestedScope

      TreeDx.Audit.append("federated.query.started", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        status: "started",
        operation: "federation.query.plan",
        requested_scope: requested
      })

      TreeDx.Audit.append(
        if(payload.rejected == [],
          do: "federated.query.completed",
          else: "federated.query.rejected"
        ),
        %{
          actor_id: principal["actorId"],
          tenant_id: principal["tenantId"],
          status: if(payload.rejected == [], do: "ok", else: "partial"),
          operation: "federation.query.plan",
          requested_scope: requested,
          effective_scope: payload.effectiveScope,
          data: %{
            rejectedCount: length(payload.rejected),
            allowedCount: length(payload.effectiveScope.repos)
          }
        }
      )

      {:ok, payload}
    end
  end

  def plan(params, principal, opts) do
    capabilities = Map.get(opts, :required_capabilities, ["files:search"])
    executable = Map.get(opts, :executable, false)

    requested = %{
      repoIds: params["repoIds"] || [],
      refs: params["refs"] || %{},
      paths: params["paths"] || %{},
      queryType: params["queryType"] || params["type"] || "text",
      capabilities: capabilities
    }

    with :ok <- validate_repo_count(requested.repoIds) do
      {allowed, rejected} =
        requested.repoIds
        |> Enum.map(
          &effective_repo_scope(
            &1,
            requested.refs[&1],
            requested.paths[&1],
            principal,
            capabilities
          )
        )
        |> Enum.reduce({[], []}, fn
          {:ok, scope}, {allowed, rejected} -> {[scope | allowed], rejected}
          {:error, entry}, {allowed, rejected} -> {allowed, [entry | rejected]}
        end)

      {:ok,
       %{
         requestedScope: requested,
         effectiveScope: %{repos: Enum.reverse(allowed)},
         rejected: Enum.reverse(rejected),
         executable: executable,
         reason: Map.get(opts, :reason)
       }}
    end
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
           TreeDx.Capabilities.require_all(principal, required_capabilities, repo_id),
         :ok <- TreeDx.Capabilities.require_ref(scope, ref),
         allowed_paths <- Enum.filter(paths, &TreeDx.Capabilities.allowed_path?(scope, &1)),
         true <- allowed_paths != [],
         {:ok, placement} when is_map(placement) <- TreeDx.Registry.placement(repo_id) do
      node_id = placement["primaryNodeId"]
      route = TreeDx.Federation.Router.route(node_id)

      {:ok,
       %{
         repoId: repo_id,
         ref: ref,
         paths: allowed_paths,
         nodeId: node_id,
         source: route.source,
         baseUrl: route.base_url,
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

  defp validate_repo_count(repo_ids) when is_list(repo_ids) do
    max_repos =
      System.get_env("TREEDX_FEDERATION_MAX_REPOS", "#{@default_max_repos}")
      |> parse_int(@default_max_repos)

    cond do
      repo_ids == [] ->
        {:error, %{code: "validation_error", message: "repoIds is required."}}

      length(repo_ids) > max_repos ->
        {:error,
         %{
           code: "validation_error",
           message: "Too many repositories requested.",
           details: %{maxRepos: max_repos}
         }}

      true ->
        :ok
    end
  end

  defp validate_repo_count(_),
    do: {:error, %{code: "validation_error", message: "repoIds must be a list."}}

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {int, ""} -> int
      _ -> default
    end
  end
end
