defmodule TreeDxWeb.FederationNodeController do
  use Phoenix.Controller, formats: [:json]
  import TreeDxWeb.ControllerHelpers

  def register(conn, params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:write"),
         {:ok, peer} <- TreeDx.Federation.Trust.put_peer(registration_peer(params)) do
      ok(conn, %{peer: sanitize(peer)})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def index(conn, _params) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:read"),
         {:ok, peers} <- TreeDx.Federation.Trust.peers() do
      ok(conn, %{peers: Enum.map(peers, &sanitize/1)})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def show(conn, %{"node_id" => node_id}) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:read"),
         {:ok, peer} when is_map(peer) <- TreeDx.Federation.Trust.get(node_id) do
      ok(conn, %{peer: sanitize(peer)})
    else
      {:ok, nil} -> error(conn, 404, %{code: "not_found", message: "Federation peer not found."})
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def trust(conn, %{"node_id" => node_id} = params) do
    states = params["trustStates"] || params["trust_states"] || []

    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:trust"),
         {:ok, peer} <- TreeDx.Federation.Trust.trust(node_id, states) do
      ok(conn, %{peer: sanitize(peer)})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  def revoke(conn, %{"node_id" => node_id}) do
    with {:ok, principal} <- require_principal(conn),
         {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "federation:trust"),
         {:ok, peer} <- TreeDx.Federation.Trust.revoke(node_id) do
      ok(conn, %{peer: sanitize(peer)})
    else
      {:error, error} -> error(conn, status_for(error[:code] || error["code"]), error)
    end
  end

  defp registration_peer(params) do
    %{
      "id" => params["nodeId"] || params["id"],
      "baseUrl" => params["baseUrl"],
      "relationship" => params["relationship"] || "child",
      "trustStates" => params["trustStates"] || ["registered"],
      "publicKeyPem" => params["publicKey"] || params["publicKeyPem"] || "",
      "canAdvertiseRepos" => params["canAdvertiseRepos"] != false,
      "canReceiveQueries" => params["canReceiveQueries"] != false,
      "canReceiveWriteProxy" => params["canReceiveWriteProxy"] == true,
      "canMirrorRepos" => params["canMirrorRepos"] == true,
      "promotionEligible" => params["promotionEligible"] == true,
      "health" => "registered"
    }
  end

  defp sanitize(peer) do
    peer
    |> Map.take([
      "id",
      "baseUrl",
      "relationship",
      "trustStates",
      "health",
      "lastSeenAt",
      "expiresAt",
      "blockedAt",
      "canAdvertiseRepos",
      "canReceiveQueries",
      "canReceiveWriteProxy",
      "canMirrorRepos",
      "promotionEligible"
    ])
    |> Map.put("nodeId", peer["id"])
  end
end
