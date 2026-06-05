defmodule TreeDbProfiler.FederationScenario do
  @moduledoc false

  alias TreeDbProfiler.{FederationAssertions, FederationTopology}

  def setup(%{opts: %{federation_mode: "single_node"}} = state), do: state

  def setup(state) do
    nodes = FederationTopology.from_opts(state.opts)

    {node_states, assertions} =
      nodes
      |> Enum.map(&prepare_node/1)
      |> Enum.reduce({[], []}, fn
        {:ok, node}, {nodes_acc, assertions_acc} ->
          {[node | nodes_acc],
           [FederationAssertions.assertion("node_#{node.id}_healthy", true) | assertions_acc]}

        {:error, node, message}, {nodes_acc, assertions_acc} ->
          {nodes_acc,
           [
             FederationAssertions.assertion("node_#{node.id}_healthy", false, message)
             | assertions_acc
           ]}
      end)

    node_states = Enum.reverse(node_states)

    assertions =
      assertions
      |> Enum.reverse()
      |> Kernel.++(bootstrap_topology(node_states, state.opts))

    federation_report = %{
      "mode" => state.opts.federation_mode,
      "nodes" => Enum.map(node_states, &Map.take(&1, [:id, :url])),
      "nodeCount" => length(node_states),
      "catalogConverged" => Enum.all?(assertions, & &1.passed),
      "proxyWritesPassed" => state.opts.federation_exercise_write_proxy,
      "mirrorReadsPassed" => state.opts.federation_mode == "mirror_cluster",
      "connectedLibraryDenialsPassed" =>
        state.opts.federation_mode == "connected_library" and
          state.opts.federation_exercise_connected_denials,
      "spilloverProbe" => %{"enabled" => false, "passed" => false, "reason" => "not_configured"}
    }

    state
    |> Map.put(:federation, federation_report)
    |> Map.put(:federation_nodes, node_states)
    |> mark_covered([
      "getFederationCatalog",
      "registerFederationNode",
      "trustFederationPeer",
      "syncFederationCatalog"
    ])
    |> Map.update(:assertions, assertions, &(&1 ++ assertions))
  end

  def setup_spillover_probe(%{opts: %{federation_mode: mode}} = state)
      when mode != "mirror_cluster",
      do:
        put_spillover_report(state, %{
          "enabled" => false,
          "passed" => false,
          "reason" => "not_mirror_cluster"
        })

  def setup_spillover_probe(state) do
    enabled? =
      System.get_env("TREEDB_PROFILE_FEDERATION_SPILLOVER_PROBE", "false") in ~w(true 1 yes on)

    if enabled? do
      do_setup_spillover_probe(state, state[:federation_nodes] || [])
    else
      put_spillover_report(state, %{"enabled" => false, "passed" => false, "reason" => "disabled"})
    end
  end

  defp do_setup_spillover_probe(state, nodes) do
    by_id = Map.new(nodes, &{&1.id, &1})
    node_a = by_id["node_a"]
    mirror_nodes = Enum.reject([by_id["node_b"], by_id["node_c"]], &is_nil/1)
    repo = state.fixture.local_repos |> List.first()
    repo_id = repo && Map.get(repo, :repo_id)

    assertions =
      if node_a && repo_id && mirror_nodes != [] do
        mirror_results =
          Enum.map(mirror_nodes, fn node ->
            mirror_id = "mirror_#{repo_id}_#{node.node_id}"

            create_result =
              post_json(node_a.url, "/api/v1/repos/#{repo_id}/mirrors", node_a.token, %{
                "id" => mirror_id,
                "sourceNodeId" => node_a.node_id,
                "targetNodeId" => node.node_id,
                "status" => "planned",
                "mode" => "read_replica"
              })

            create? = match?({:ok, %{"ok" => true}}, create_result)

            sync_result =
              if create? do
                post_json(
                  node_a.url,
                  "/api/v1/repos/#{repo_id}/mirrors/#{mirror_id}/sync",
                  node_a.token,
                  %{}
                )
              else
                {:error, "mirror create failed"}
              end

            sync? = match?({:ok, %{"ok" => true}}, sync_result)

            %{
              node: node,
              mirror_id: mirror_id,
              create?: create?,
              sync?: sync?,
              create_result: create_result,
              sync_result: sync_result
            }
          end)

        mirror_assertions =
          Enum.flat_map(mirror_results, fn result ->
            [
              FederationAssertions.assertion(
                "spillover_create_mirror_#{result.node.node_id}",
                result.create?,
                result_message(result.create_result)
              ),
              FederationAssertions.assertion(
                "spillover_sync_mirror_#{result.node.node_id}",
                result.sync?,
                result_message(result.sync_result)
              )
            ]
          end)

        mirror_setup_ok? = Enum.all?(mirror_results, &(&1.create? and &1.sync?))

        placement? =
          mirror_setup_ok? and
            match?(
              {:ok, %{"ok" => true}},
              post_json(
                node_a.url,
                "/api/v1/registry/repos/#{repo_id}/placement",
                node_a.token,
                %{
                  "primaryNodeId" => node_a.node_id,
                  "mirrorNodeIds" => Enum.map(mirror_nodes, & &1.node_id),
                  "readPolicy" => "primary_or_healthy_mirror",
                  "writePolicy" => "primary_proxy",
                  "migrationState" => "stable"
                }
              )
            )

        {sync_assertions, read_ok?, route} =
          if placement? do
            sync_assertions = sync_all(nodes)
            {read_ok?, route} = spillover_read(node_a, repo_id, repo)
            {sync_assertions, read_ok?, route}
          else
            {[], false, nil}
          end

        mirror_assertions ++
          [
            FederationAssertions.assertion("spillover_update_placement", placement?),
            FederationAssertions.assertion("spillover_remote_mirror_read", read_ok?)
          ] ++
          sync_assertions ++
          [
            FederationAssertions.assertion(
              "spillover_route_header_remote_mirror",
              route in ["remote_mirror", "spillover"]
            )
          ]
      else
        [FederationAssertions.assertion("spillover_setup_state_available", false)]
      end

    passed? = Enum.all?(assertions, & &1.passed)

    report = %{
      "enabled" => true,
      "passed" => passed?,
      "repoId" => repo_id,
      "mirrorNodeIds" => Enum.map(mirror_nodes, & &1.node_id)
    }

    state
    |> put_spillover_report(report)
    |> Map.update(:assertions, assertions, &(&1 ++ assertions))
  end

  defp result_message({:ok, _}), do: nil
  defp result_message({:error, message}) when is_binary(message), do: message
  defp result_message(other), do: inspect(other)

  defp put_spillover_report(state, report) do
    update_in(state, [:federation], fn federation ->
      federation = federation || %{}
      Map.put(federation, "spilloverProbe", report)
    end)
  end

  defp spillover_read(nil, _repo_id, _repo), do: {false, nil}
  defp spillover_read(_node_a, nil, _repo), do: {false, nil}

  defp spillover_read(node_a, repo_id, repo) do
    path =
      repo.files
      |> Enum.find_value(fn file ->
        if String.ends_with?(file.path, [".md", ".txt"]), do: file.path
      end) || "docs/topic-01/doc-000001.md"

    case Req.post(node_a.url <> "/api/v1/repos/#{repo_id}/files/read",
           headers: auth(node_a.token),
           json: %{"path" => path, "ref" => "refs/heads/main", "parseFrontmatter" => true},
           receive_timeout: 120_000,
           retry: false
         ) do
      {:ok, %{status: status, headers: headers, body: body}} when status in 200..299 ->
        route =
          headers
          |> Enum.find_value(fn
            {"x-treedb-route-reason", value} ->
              header_value(value)

            {key, value} when is_binary(key) ->
              if String.downcase(key) == "x-treedb-route-reason", do: header_value(value)

            _ ->
              nil
          end)

        {get_in(body, ["file", "path"]) == path, route}

      _ ->
        {false, nil}
    end
  end

  defp header_value([value | _]), do: value
  defp header_value(value), do: value

  defp mark_covered(state, operation_ids) do
    Map.update(state, :covered_operation_ids, operation_ids, fn existing ->
      (List.wrap(existing) ++ operation_ids)
      |> Enum.uniq()
    end)
  end

  defp prepare_node(%{id: id, url: url}) do
    base_url = String.trim_trailing(url, "/")

    with {:ok, token} <- dev_token(base_url),
         {:ok, %{"ok" => true}} <- get_json(base_url, "/api/v1/health", token),
         {:ok, %{"ok" => true, "catalog" => catalog}} <-
           get_json(base_url, "/api/v1/federation/catalog", token) do
      {:ok,
       %{
         id: id,
         url: base_url,
         token: token,
         catalog: catalog,
         node_id: get_in(catalog, ["node", "nodeId"]) || id,
         public_key: get_in(catalog, ["node", "publicKey"]) || "",
         base_url: get_in(catalog, ["node", "baseUrl"]) || base_url
       }}
    else
      {:error, message} -> {:error, %{id: id}, message}
      other -> {:error, %{id: id}, inspect(other)}
    end
  end

  defp bootstrap_topology(nodes, opts) do
    by_id = Map.new(nodes, &{&1.id, &1})
    node_a = by_id["node_a"]
    node_b = by_id["node_b"]
    node_c = by_id["node_c"]

    []
    |> maybe_register_and_trust(node_a, node_b, trust_states(opts))
    |> maybe_register_and_trust(node_a, node_c, trust_states(opts))
    |> maybe_register_and_trust(node_b, node_a, parent_trust_states(opts))
    |> maybe_register_and_trust(node_c, node_a, parent_trust_states(opts))
    |> maybe_register_and_trust(node_c, node_b, parent_trust_states(opts))
    |> Kernel.++(sync_all(nodes))
  end

  defp maybe_register_and_trust(assertions, nil, _child, _states), do: assertions
  defp maybe_register_and_trust(assertions, _parent, nil, _states), do: assertions

  defp maybe_register_and_trust(assertions, parent, child, states) do
    register_body = %{
      "nodeId" => child.node_id,
      "baseUrl" => child.base_url,
      "relationship" => "peer",
      "trustStates" => ["registered"],
      "publicKey" => child.public_key,
      "canAdvertiseRepos" => true,
      "canReceiveQueries" => true,
      "canReceiveWriteProxy" => "trusted_for_write_proxy" in states,
      "canMirrorRepos" => "trusted_for_mirror" in states,
      "promotionEligible" => "trusted_for_mirror" in states
    }

    registered? =
      match?(
        {:ok, %{"ok" => true}},
        post_json(parent.url, "/api/v1/federation/nodes/register", parent.token, register_body)
      )

    trusted? =
      match?(
        {:ok, %{"ok" => true}},
        post_json(parent.url, "/api/v1/federation/peers/#{child.node_id}/trust", parent.token, %{
          "trustStates" => states
        })
      )

    assertions ++
      [
        FederationAssertions.assertion(
          "register_#{child.node_id}_on_#{parent.node_id}",
          registered?
        ),
        FederationAssertions.assertion("trust_#{child.node_id}_on_#{parent.node_id}", trusted?)
      ]
  end

  defp sync_all(nodes) do
    Enum.map(nodes, fn node ->
      ok? =
        match?(
          {:ok, %{"ok" => true}},
          post_json(node.url, "/api/v1/federation/catalog/sync", node.token, %{})
        )

      FederationAssertions.assertion("sync_#{node.node_id}", ok?)
    end)
  end

  defp trust_states(%{federation_mode: "mirror_cluster"}),
    do:
      ~w(registered trusted_for_catalog trusted_for_query trusted_for_write_proxy trusted_for_mirror)

  defp trust_states(%{federation_mode: "connected_library"}),
    do: ~w(registered trusted_for_catalog trusted_for_query)

  defp parent_trust_states(%{federation_mode: "mirror_cluster"}),
    do:
      ~w(registered trusted_for_catalog trusted_for_query trusted_for_write_proxy trusted_for_mirror)

  defp parent_trust_states(_opts), do: ~w(registered trusted_for_catalog trusted_for_query)

  defp dev_token(base_url) do
    case Req.post(base_url <> "/api/v1/auth/dev-token",
           json: %{},
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok,
         body["accessToken"] || body["token"] || get_in(body, ["token", "accessToken"]) ||
           get_in(body, ["auth", "token"])}

      {:ok, response} ->
        {:error, "dev token request failed with #{response.status}"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp get_json(base_url, path, token) do
    case Req.get(base_url <> path, headers: auth(token), receive_timeout: 30_000, retry: false) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, response} -> {:error, "GET #{path} failed with #{response.status}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp post_json(base_url, path, token, body) do
    case Req.post(base_url <> path,
           headers: auth(token),
           json: body,
           receive_timeout: 30_000,
           retry: false
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, response} -> {:error, "POST #{path} failed with #{response.status}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp auth(nil), do: []
  defp auth(token), do: [{"authorization", "Bearer #{token}"}]
end
