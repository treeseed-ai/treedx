defmodule TreeDx.Federation.Trust do
  @moduledoc false

  @default_trust ~w(trusted_for_catalog)

  def bootstrap_parents! do
    TreeDx.Federation.NodeIdentity.ensure_keys!()

    parents()
    |> Enum.each(fn {node_id, base_url} ->
      trust_states =
        if System.get_env("TREEDX_FEDERATION_AUTO_TRUST_PARENTS", "true") in ["false", "0"] do
          []
        else
          @default_trust
        end

      put_peer(%{
        "id" => node_id,
        "baseUrl" => base_url,
        "relationship" => "parent",
        "trustStates" => trust_states,
        "discoveredViaNodeId" => nil,
        "parentNodeIds" => [],
        "publicKeyPem" => "",
        "acceptedIssuerIds" => [],
        "allowedCapabilities" => [],
        "canAdvertiseRepos" => true,
        "canReceiveQueries" => true,
        "canReceiveWriteProxy" => true,
        "canMirrorRepos" => true,
        "promotionEligible" => true,
        "health" => "unknown",
        "lastSeenAt" => now(),
        "expiresAt" => nil,
        "blockedAt" => nil
      })
    end)
  end

  def put_peer(peer), do: TreeDx.Store.put_federation_peer(normalize(peer))
  def peers, do: TreeDx.Store.list_federation_peers()
  def get(node_id), do: TreeDx.Store.get_federation_peer(node_id)

  def trust(node_id, states) do
    with {:ok, peer} when is_map(peer) <- get(node_id) do
      peer
      |> Map.put("trustStates", Enum.uniq(states))
      |> Map.put("blockedAt", nil)
      |> Map.put("lastSeenAt", now())
      |> put_peer()
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Federation peer not found."}}
      other -> other
    end
  end

  def revoke(node_id) do
    with {:ok, peer} when is_map(peer) <- get(node_id) do
      peer
      |> Map.put("trustStates", [])
      |> Map.put("health", "blocked")
      |> Map.put("blockedAt", now())
      |> put_peer()
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Federation peer not found."}}
      other -> other
    end
  end

  def trusted?(node_id, state) do
    with {:ok, peer} when is_map(peer) <- get(node_id) do
      state in (peer["trustStates"] || []) and is_nil(peer["blockedAt"])
    else
      _ -> false
    end
  end

  def parents do
    System.get_env("TREEDX_FEDERATION_PARENTS", "")
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [node_id, base_url] when node_id != "" and base_url != "" -> [{node_id, base_url}]
        _ -> []
      end
    end)
  end

  defp normalize(peer) do
    %{
      id: peer["id"] || peer[:id],
      baseUrl: peer["baseUrl"] || peer[:baseUrl] || "",
      relationship: peer["relationship"] || peer[:relationship] || "peer",
      trustStates: peer["trustStates"] || peer[:trustStates] || [],
      discoveredViaNodeId: peer["discoveredViaNodeId"] || peer[:discoveredViaNodeId],
      parentNodeIds: peer["parentNodeIds"] || peer[:parentNodeIds] || [],
      publicKeyPem: peer["publicKeyPem"] || peer[:publicKeyPem] || "",
      acceptedIssuerIds: peer["acceptedIssuerIds"] || peer[:acceptedIssuerIds] || [],
      allowedCapabilities: peer["allowedCapabilities"] || peer[:allowedCapabilities] || [],
      canAdvertiseRepos: truthy?(peer["canAdvertiseRepos"] || peer[:canAdvertiseRepos]),
      canReceiveQueries: truthy?(peer["canReceiveQueries"] || peer[:canReceiveQueries]),
      canReceiveWriteProxy: truthy?(peer["canReceiveWriteProxy"] || peer[:canReceiveWriteProxy]),
      canMirrorRepos: truthy?(peer["canMirrorRepos"] || peer[:canMirrorRepos]),
      promotionEligible: truthy?(peer["promotionEligible"] || peer[:promotionEligible]),
      health: peer["health"] || peer[:health] || "unknown",
      lastSeenAt: peer["lastSeenAt"] || peer[:lastSeenAt] || now(),
      expiresAt: peer["expiresAt"] || peer[:expiresAt],
      blockedAt: peer["blockedAt"] || peer[:blockedAt]
    }
  end

  defp truthy?(value), do: value in [true, "true", "1", 1]
  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
