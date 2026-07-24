defmodule TreeDx.Federation.Catalog do
  @moduledoc false

  def local do
    {:ok, repos} = TreeDx.Store.list_repositories()
    {:ok, placements} = local_routes()
    {:ok, peers} = TreeDx.Store.list_federation_peers()
    {:ok, capacity} = TreeDx.Store.list_node_capacity()

    payload = %{
      "version" => 1,
      "generatedAt" => now(),
      "node" => %{
        "nodeId" => TreeDx.Federation.NodeIdentity.node_id(),
        "baseUrl" => TreeDx.Federation.NodeIdentity.base_url(),
        "publicKey" => TreeDx.Federation.NodeIdentity.public_key_pem(),
        "health" => "healthy"
      },
      "lineage" => %{
        "parentNodeIds" => Enum.map(TreeDx.Federation.Trust.parents(), &elem(&1, 0)),
        "discoveredViaNodeId" => nil
      },
      "peers" => Enum.map(peers, &public_peer/1),
      "repositories" => Enum.map(repos, &advertisement(&1, placements)),
      "routes" => Enum.map(placements, &public_route/1),
      "capacity" => capacity,
      "mirrors" => []
    }

    TreeDx.Federation.NodeIdentity.signed(payload)
  end

  def import(catalog, discovered_via \\ nil) do
    with :ok <- validate_catalog(catalog) do
      import_node(catalog["node"], discovered_via)

      catalog
      |> Map.get("repositories", [])
      |> Enum.each(&TreeDx.Store.put_repository_advertisement/1)

      catalog
      |> Map.get("routes", [])
      |> Enum.each(&TreeDx.Store.put_federation_route/1)

      :ok
    end
  end

  def routes do
    with {:ok, routes} <- TreeDx.Store.list_federation_routes() do
      {:ok, Enum.map(routes, &public_route/1)}
    end
  end

  defp local_routes do
    with {:ok, repos} <- TreeDx.Store.list_repositories() do
      routes =
        Enum.flat_map(repos, fn repo ->
          case TreeDx.Store.get_repository_placement(repo["id"]) do
            {:ok, placement} when is_map(placement) ->
              [route_from_repo(repo, placement)]

            _ ->
              []
          end
        end)

      {:ok, routes}
    end
  end

  defp route_from_repo(repo, placement) do
    %{
      "repositoryId" => repo["id"],
      "repositoryName" => repo["repositoryName"] || repo["name"],
      "primaryNodeId" => placement["primaryNodeId"],
      "mirrorNodeIds" => placement["mirrorNodeIds"] || [],
      "readPolicy" => placement["readPolicy"] || "primary_or_mirror",
      "writePolicy" => placement["writePolicy"] || "primary_only",
      "ownerNodeId" => placement["primaryNodeId"],
      "source" => "local",
      "confidence" => "authoritative",
      "freshness" => %{"status" => "current"},
      "catalogVersion" => System.system_time(:second),
      "lastSeenAt" => now(),
      "expiresAt" => nil
    }
  end

  defp advertisement(repo, routes) do
    route = Enum.find(routes, &(&1["repositoryId"] == repo["id"])) || %{}

    %{
      "repositoryId" => repo["id"],
      "repositoryName" => repo["repositoryName"] || repo["name"],
      "ownerNodeId" => route["ownerNodeId"] || TreeDx.Federation.NodeIdentity.node_id(),
      "advertisedByNodeId" => TreeDx.Federation.NodeIdentity.node_id(),
      "defaultRef" => repo["defaultRef"] || "refs/heads/main",
      "refs" => ["refs/heads/main"],
      "paths" => ["**"],
      "capabilities" => ["files:read", "files:search", "graph:query"],
      "visibility" => "trusted_federation",
      "graphAvailable" => true,
      "snapshotsAvailable" => true,
      "mirrorEligible" => true,
      "catalogVersion" => System.system_time(:second),
      "lastSeenAt" => now(),
      "expiresAt" => nil
    }
  end

  defp import_node(nil, _), do: :ok

  defp import_node(node, discovered_via) do
    existing =
      case TreeDx.Federation.Trust.get(node["nodeId"]) do
        {:ok, peer} when is_map(peer) -> peer
        _ -> %{}
      end

    TreeDx.Federation.Trust.put_peer(%{
      "id" => node["nodeId"],
      "baseUrl" => node["baseUrl"],
      "relationship" =>
        existing["relationship"] || if(discovered_via, do: "discovered", else: "peer"),
      "trustStates" => existing["trustStates"] || [],
      "discoveredViaNodeId" => existing["discoveredViaNodeId"] || discovered_via,
      "parentNodeIds" => existing["parentNodeIds"] || [],
      "publicKeyPem" => node["publicKey"] || "",
      "acceptedIssuerIds" => [],
      "allowedCapabilities" => [],
      "canAdvertiseRepos" => existing["canAdvertiseRepos"] || true,
      "canReceiveQueries" => existing["canReceiveQueries"] || true,
      "canReceiveWriteProxy" => existing["canReceiveWriteProxy"] || false,
      "canMirrorRepos" => existing["canMirrorRepos"] || false,
      "promotionEligible" => existing["promotionEligible"] || false,
      "health" => node["health"] || "unknown",
      "lastSeenAt" => now()
    })
  end

  defp validate_catalog(%{"node" => %{"nodeId" => node_id}}) when is_binary(node_id), do: :ok

  defp validate_catalog(_),
    do: {:error, %{code: "validation_error", message: "Invalid federation catalog."}}

  defp public_peer(peer) do
    Map.take(peer, [
      "id",
      "baseUrl",
      "relationship",
      "trustStates",
      "health",
      "lastSeenAt",
      "expiresAt"
    ])
  end

  defp public_route(route) do
    route
    |> Map.take([
      "repositoryId",
      "repositoryName",
      "primaryNodeId",
      "mirrorNodeIds",
      "readPolicy",
      "writePolicy",
      "ownerNodeId",
      "source",
      "confidence",
      "freshness",
      "lastSeenAt",
      "expiresAt"
    ])
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
