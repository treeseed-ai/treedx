defmodule TreeDx.Federation.RouteTable do
  @moduledoc false

  def resolve(repo_id) do
    local_node = TreeDx.Federation.NodeIdentity.node_id()

    with {:ok, placement} when is_map(placement) <- TreeDx.Store.get_repository_placement(repo_id) do
      source = if placement["primaryNodeId"] == local_node, do: "local", else: "remote"

      {:ok,
       %{
         "repositoryId" => repo_id,
         "primaryNodeId" => placement["primaryNodeId"],
         "mirrorNodeIds" => placement["mirrorNodeIds"] || [],
         "readPolicy" => placement["readPolicy"] || "primary_or_mirror",
         "writePolicy" => placement["writePolicy"] || "primary_only",
         "source" => source,
         "baseUrl" => base_url(placement["primaryNodeId"])
       }}
    else
      _ ->
        case TreeDx.Store.get_federation_route(repo_id) do
          {:ok, route} when is_map(route) ->
            {:ok, Map.put(route, "baseUrl", base_url(route["primaryNodeId"]))}

          _ ->
            {:error,
             %{
               code: "federated_route_not_configured",
               message: "Federated route is not configured."
             }}
        end
    end
  end

  def resolve_repo(repo_id_or_name, opts \\ []) do
    repo_id = resolve_repo_id(repo_id_or_name)

    case Keyword.get(opts, :mode, :read) do
      :write -> resolve_write(repo_id, opts)
      :read -> resolve_read(repo_id, opts)
      _ -> resolve(repo_id)
    end
  end

  def resolve_read(repo_id, opts \\ []) do
    with {:ok, route} <- resolve(repo_id) do
      case resolve_read_candidate(route, opts) do
        nil ->
          {:error,
           %{
             code: "federated_route_not_configured",
             message: "Federated read route is not configured."
           }}

        candidate ->
          {:ok, candidate}
      end
    end
  end

  def resolve_read_candidate(route_or_repo_id, opts \\ [])

  def resolve_read_candidate(route, opts) when is_map(route) do
    route
    |> read_candidates(opts)
    |> order_read_candidates(Keyword.get(opts, :pool, :repository_query), opts)
    |> List.first()
  end

  def resolve_read_candidate(repo_id, opts) do
    with {:ok, route} <- resolve(repo_id), do: resolve_read_candidate(route, opts)
  end

  def read_candidates(route_or_repo_id, opts \\ [])

  def read_candidates(route, opts) when is_map(route) do
    repo_id = route["repositoryId"]
    local_node = TreeDx.Federation.NodeIdentity.node_id()
    pool = Keyword.get(opts, :pool, :repository_query)
    allow_mirrors? = Keyword.get(opts, :allow_mirrors?, true)
    allow_remote_primary? = Keyword.get(opts, :allow_remote_primary?, true)

    []
    |> maybe_add(route["primaryNodeId"] == local_node, fn ->
      candidate(route, "local", local_node, "local_primary", nil, pool)
    end)
    |> maybe_add(
      allow_mirrors? and read_from_mirrors?() and local_node in (route["mirrorNodeIds"] || []) and
        mirror_fresh?(repo_id, local_node, opts),
      fn -> candidate(route, "mirror", local_node, "local_mirror", nil, pool) end
    )
    |> add_remote_mirrors(route, opts)
    |> maybe_add(
      allow_remote_primary? and route["primaryNodeId"] != local_node and
        trusted_query?(route["primaryNodeId"]),
      fn ->
        candidate(
          route,
          "remote",
          route["primaryNodeId"],
          "remote_primary",
          base_url(route["primaryNodeId"]),
          pool
        )
      end
    )
  end

  def read_candidates(repo_id, opts) do
    with {:ok, route} <- resolve(repo_id), do: read_candidates(route, opts), else: (_ -> [])
  end

  def resolve_write(repo_id, _opts \\ []) do
    with {:ok, route} <- resolve(repo_id) do
      local_node = TreeDx.Federation.NodeIdentity.node_id()

      cond do
        route["primaryNodeId"] == local_node ->
          {:ok, Map.merge(route, %{"source" => "local", "servedByNodeId" => local_node})}

        not write_proxy_enabled?() ->
          {:error, write_route_required(repo_id, route)}

        trusted_write_proxy?(route["primaryNodeId"]) ->
          {:ok,
           Map.merge(route, %{"source" => "remote", "servedByNodeId" => route["primaryNodeId"]})}

        true ->
          {:error,
           %{
             code: "federated_node_auth_forbidden",
             message: "Federated primary is not trusted for write proxy."
           }}
      end
    end
  end

  def resolve_workspace(workspace_id, opts \\ []) do
    local_node = TreeDx.Federation.NodeIdentity.node_id()

    with {:ok, route} when is_map(route) <- TreeDx.Store.get_workspace_route(workspace_id) do
      if route["nodeId"] == local_node do
        {:ok, Map.merge(route, %{"source" => "local", "servedByNodeId" => local_node})}
      else
        resolve_workspace_route(route, opts)
      end
    else
      _ ->
        case TreeDx.Store.get_workspace(workspace_id) do
          {:ok, workspace} ->
            {:ok,
             %{
               "workspaceId" => workspace_id,
               "repositoryId" => workspace["repoId"],
               "nodeId" => local_node,
               "source" => "local",
               "servedByNodeId" => local_node
             }}

          _ ->
            {:error, %{code: "not_found", message: "Workspace not found."}}
        end
    end
  end

  def local_primary?(repo_id) do
    with {:ok, route} <- resolve(repo_id) do
      route["primaryNodeId"] == TreeDx.Federation.NodeIdentity.node_id()
    else
      _ -> false
    end
  end

  def route_status(repo_id) do
    case resolve(repo_id) do
      {:ok, route} ->
        Map.take(route, ["repositoryId", "primaryNodeId", "mirrorNodeIds", "source"])

      {:error, error} ->
        %{"repositoryId" => repo_id, "status" => "unresolved", "error" => error[:code]}
    end
  end

  defp base_url(node_id) do
    cond do
      node_id == TreeDx.Federation.NodeIdentity.node_id() ->
        nil

      true ->
        case TreeDx.Store.get_federation_peer(node_id) do
          {:ok, peer} when is_map(peer) -> peer["baseUrl"]
          _ -> nil
        end
    end
  end

  defp order_read_candidates(candidates, pool, opts) do
    if load_aware_reads?() and Keyword.get(opts, :prefer_spillover?, true) do
      threshold = load_aware_threshold()

      {local, remote} =
        Enum.split_with(candidates, fn candidate ->
          candidate["servedByNodeId"] == TreeDx.Federation.NodeIdentity.node_id()
        end)

      local_pressure =
        local
        |> Enum.map(&get_in(&1, ["load", "pressure"]))
        |> Enum.map(&TreeDx.Federation.NodeLoad.pressure_rank/1)
        |> Enum.min(fn -> 0 end)

      if local != [] and
           local_pressure < TreeDx.Federation.NodeLoad.pressure_rank(threshold) do
        local ++ TreeDx.Federation.NodeLoad.compare_candidates(remote, pool)
      else
        TreeDx.Federation.NodeLoad.compare_candidates(remote, pool) ++ local
      end
    else
      candidates
    end
  end

  defp add_remote_mirrors(candidates, route, opts) do
    repo_id = route["repositoryId"]
    pool = Keyword.get(opts, :pool, :repository_query)
    local_node = TreeDx.Federation.NodeIdentity.node_id()
    allow_mirrors? = Keyword.get(opts, :allow_mirrors?, true)

    if allow_mirrors? and read_from_mirrors?() do
      route
      |> Map.get("mirrorNodeIds", [])
      |> Enum.reject(&(&1 == local_node))
      |> Enum.filter(&(trusted_query?(&1) and mirror_fresh?(repo_id, &1, opts)))
      |> Enum.reduce(candidates, fn node_id, acc ->
        maybe_add(acc, true, fn ->
          candidate(route, "remote", node_id, "remote_mirror", base_url(node_id), pool)
        end)
      end)
    else
      candidates
    end
  end

  defp maybe_add(candidates, true, fun), do: candidates ++ [fun.()]
  defp maybe_add(candidates, _false, _fun), do: candidates

  defp candidate(route, source, node_id, reason, base_url, pool) do
    load =
      if node_id == TreeDx.Federation.NodeIdentity.node_id() do
        TreeDx.Federation.NodeLoad.local_pool_load(pool)
      else
        TreeDx.Federation.NodeLoad.load_for_candidate(%{"servedByNodeId" => node_id}, pool)
      end

    route
    |> Map.merge(%{
      "source" => source,
      "servedByNodeId" => node_id,
      "baseUrl" => base_url,
      "reason" => reason,
      "load" => load
    })
  end

  defp resolve_repo_id(repo_id_or_name) do
    value = to_string(repo_id_or_name)

    cond do
      String.starts_with?(value, "repo_") ->
        value

      true ->
        normalized = TreeDx.RepositoryStorage.normalize_name(value)

        with {:ok, repos} <- TreeDx.Store.list_repositories(),
             repo when is_map(repo) <-
               Enum.find(
                 repos,
                 &((&1["repositoryName"] || &1["name"]) |> to_string() == normalized)
               ) do
          repo["id"]
        else
          _ ->
            case TreeDx.Store.list_federation_routes() do
              {:ok, routes} when is_list(routes) ->
                case Enum.find(routes, &(&1["repositoryName"] == normalized)) do
                  %{"repositoryId" => repo_id} -> repo_id
                  _ -> value
                end

              _ ->
                value
            end
        end
    end
  end

  defp resolve_workspace_route(route, _opts) do
    node_id = route["nodeId"]

    with true <- trusted_write_proxy?(node_id) or trusted_query?(node_id),
         {:ok, peer} when is_map(peer) <- TreeDx.Store.get_federation_peer(node_id),
         base_url when is_binary(base_url) and base_url != "" <- peer["baseUrl"] do
      {:ok,
       Map.merge(route, %{
         "source" => "remote",
         "servedByNodeId" => node_id,
         "baseUrl" => base_url
       })}
    else
      _ ->
        {:error,
         %{code: "federated_route_not_configured", message: "Workspace route is not configured."}}
    end
  end

  defp trusted_query?(node_id), do: TreeDx.Federation.Trust.trusted?(node_id, "trusted_for_query")

  defp trusted_write_proxy?(node_id),
    do: TreeDx.Federation.Trust.trusted?(node_id, "trusted_for_write_proxy")

  defp write_proxy_enabled?,
    do: System.get_env("TREEDX_FEDERATION_WRITE_PROXY_ENABLED", "true") not in ["false", "0"]

  defp read_from_mirrors?,
    do: System.get_env("TREEDX_FEDERATION_READ_FROM_MIRRORS", "true") not in ["false", "0"]

  defp load_aware_reads?,
    do: System.get_env("TREEDX_FEDERATION_LOAD_AWARE_READS", "true") not in ["false", "0"]

  defp load_aware_threshold,
    do: System.get_env("TREEDX_FEDERATION_LOAD_AWARE_READ_PRESSURE", "moderate")

  defp mirror_fresh?(repo_id, node_id, _opts) do
    fresh_assignment?(repo_id, node_id) or fresh_public_mirror?(repo_id, node_id)
  end

  defp fresh_assignment?(repo_id, node_id) do
    case TreeDx.Store.list_mirror_assignments(repo_id) do
      {:ok, assignments} when is_list(assignments) ->
        Enum.any?(assignments, fn assignment ->
          assignment["targetNodeId"] == node_id and assignment["status"] in ["healthy", "synced"] and
            fresh_enough?(assignment["lastSyncAt"] || assignment["lastSyncedAt"])
        end)

      _ ->
        false
    end
  end

  defp fresh_public_mirror?(repo_id, node_id) do
    case TreeDx.Store.list_mirrors(repo_id) do
      {:ok, mirrors} when is_list(mirrors) ->
        Enum.any?(mirrors, fn mirror ->
          mirror["targetNodeId"] == node_id and mirror["status"] in ["healthy", "synced"] and
            mirror["behindBy"] in [nil, 0]
        end)

      _ ->
        false
    end
  end

  defp fresh_enough?(nil), do: true

  defp fresh_enough?(timestamp) do
    max_age =
      System.get_env("TREEDX_FEDERATION_MAX_MIRROR_STALENESS_MS", "30000") |> String.to_integer()

    case DateTime.from_iso8601(timestamp) do
      {:ok, synced_at, _} -> DateTime.diff(DateTime.utc_now(), synced_at, :millisecond) <= max_age
      _ -> false
    end
  end

  defp write_route_required(repo_id, route) do
    %{
      code: "write_route_required",
      message: "Repository writes must be sent to the primary node.",
      details: %{repoId: repo_id, primaryNodeId: route["primaryNodeId"]}
    }
  end
end
