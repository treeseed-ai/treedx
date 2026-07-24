defmodule TreeDxProfiler.ScenarioGraphSetup do
  @moduledoc false

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_ok: 1,
      assert_ok_or_forbidden: 1,
      assert_ok_or_not_found: 1,
      assert_ok_or_validation: 1,
      call: 7,
      call!: 7,
      call!: 8
    ]

  def refresh_graph_and_index(state) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"
    paths = ["docs/**", "plain/**", "data/**"]

    {state, refresh} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/refresh",
        "refreshRepositoryGraph",
        "graph",
        %{"ref" => ref, "paths" => paths, "incremental" => false},
        expected: 200,
        assert: &assert_ok/1
      )

    job_id = refresh["jobId"] || get_in(refresh, ["graph", "jobId"])

    state =
      if job_id do
        call!(
          state,
          :get,
          "/api/v1/repos/#{repo_id}/graph/refresh-jobs/#{job_id}",
          "getGraphRefreshJob",
          "graph",
          nil,
          &assert_ok/1
        )
      else
        state
      end

    state =
      call!(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/query",
        "queryRepositoryGraph",
        "graph",
        %{"ref" => ref, "query" => "release", "options" => %{"limit" => 20}},
        &assert_ok/1
      )

    {state, files} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/graph/search-files",
        "searchGraphFiles",
        "graph",
        %{"ref" => ref, "query" => "release", "limit" => 20},
        expected: 200,
        assert: &assert_ok/1
      )

    graph_node_id = get_in(files, ["results", Access.at(0), "node", "id"])

    state
    |> Map.put(:graph_node_id, graph_node_id)
    |> maybe_get_graph_node(repo_id, ref)
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/search-sections",
      "searchGraphSections",
      "graph",
      %{"ref" => ref, "query" => "release", "limit" => 20},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/search-entities",
      "searchGraphEntities",
      "graph",
      %{"ref" => ref, "query" => "release", "limit" => 20},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/related",
      "getRelatedGraphNodes",
      "graph",
      related_graph_body(ref, graph_node_id),
      &assert_ok_or_validation/1,
      expected: [200, 422]
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/graph/subgraph",
      "getGraphSubgraph",
      "graph",
      %{
        "ref" => ref,
        "seedIds" => List.wrap(graph_node_id) |> Enum.reject(&is_nil/1),
        "options" => %{"limit" => 5}
      },
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/context/build",
      "buildContext",
      "context",
      %{"ref" => ref, "query" => "release", "budget" => %{"maxNodes" => 10, "maxTokens" => 2000}},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/context/parse-ctx",
      "parseContextQuery",
      "context",
      %{"ctx" => "release"},
      &assert_ok_or_validation/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/search/index/refresh",
      "refreshSearchIndex",
      "search",
      %{"ref" => ref, "paths" => paths, "incremental" => false},
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/search/index/status",
      "getSearchIndexStatus",
      "search",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/repos/#{repo_id}/search/index/compact",
      "compactSearchIndex",
      "search",
      %{"planOnly" => true},
      &assert_ok_or_forbidden/1
    )
  end

  defp maybe_get_graph_node(%{graph_node_id: node_id} = state, repo_id, ref)
       when is_binary(node_id) do
    call!(
      state,
      :get,
      "/api/v1/repos/#{repo_id}/graph/nodes/#{node_id}?ref=#{URI.encode_www_form(ref)}",
      "getGraphNode",
      "graph",
      nil,
      &assert_ok/1
    )
  end

  defp maybe_get_graph_node(state, _repo_id, _ref), do: state

  defp related_graph_body(ref, node_id) when is_binary(node_id) do
    %{
      "ref" => ref,
      "nodeId" => node_id,
      "relations" => ["references"],
      "options" => %{"limit" => 5}
    }
  end

  defp related_graph_body(ref, _node_id),
    do: %{"ref" => ref, "options" => %{"limit" => 5}}

  def build_snapshot_artifact(state) do
    repo_id = primary_repo(state).repo_id
    ref = state.branch_name || "refs/heads/main"

    {state, snapshot} =
      call(
        state,
        :post,
        "/api/v1/repos/#{repo_id}/snapshots/build",
        "buildSnapshot",
        "snapshot",
        %{
          "ref" => ref,
          "kind" => "repository_snapshot",
          "paths" => ["docs/**"],
          "includeGraph" => true
        },
        expected: 200,
        assert: &assert_ok/1
      )

    snapshot_id = get_in(snapshot, ["snapshot", "snapshotId"])

    state =
      if snapshot_id do
        call!(
          state,
          :get,
          "/api/v1/repos/#{repo_id}/snapshots/#{snapshot_id}",
          "getSnapshot",
          "snapshot",
          nil,
          &assert_ok/1
        )
      else
        state
      end

    {state, artifact} =
      if snapshot_id do
        call(
          state,
          :post,
          "/api/v1/repos/#{repo_id}/artifacts/export",
          "exportArtifact",
          "artifact",
          %{"snapshotId" => snapshot_id},
          expected: 200,
          assert: &assert_ok/1
        )
      else
        {state, %{}}
      end

    artifact_id = get_in(artifact, ["artifact", "artifactId"])

    state
    |> Map.put(:snapshot_id, snapshot_id)
    |> Map.put(:artifact_id, artifact_id)
    |> call!(
      :get,
      "/api/v1/repos/#{repo_id}/artifacts",
      "listArtifacts",
      "artifact",
      nil,
      &assert_ok/1
    )
    |> maybe_get_artifact(repo_id, artifact_id)
  end

  defp maybe_get_artifact(state, _repo_id, nil), do: state

  defp maybe_get_artifact(state, repo_id, artifact_id),
    do:
      call!(
        state,
        :get,
        "/api/v1/repos/#{repo_id}/artifacts/#{artifact_id}",
        "getArtifact",
        "artifact",
        nil,
        &assert_ok_or_not_found/1,
        expected: [200, 404]
      )

  defp primary_repo(state), do: hd(state.fixture.local_repos)
end
