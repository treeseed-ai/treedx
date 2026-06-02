defmodule TreeDbWeb.EndToEndMvpTest do
  use TreeDbWeb.ConnCase, async: false

  test "authenticated registry-aware repository loop survives restart", %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_a_path = Path.join(data_dir, "repos/bare/e2e-repo-a")
    repo_b_path = Path.join(data_dir, "repos/bare/e2e-repo-b")
    create_git_repo!(repo_a_path)
    create_git_repo!(repo_b_path, message: "Initial fixture B")

    token = dev_token!(conn)

    {:ok, _} =
      TreeDb.Store.seed_local_records("node_mirror", "http://node-mirror.example.invalid")

    repo_a_response =
      register_repo!(build_conn(), token, %{"name" => "e2e-repo-a", "localPath" => repo_a_path})

    repo_b_response =
      register_repo!(build_conn(), token, %{"name" => "e2e-repo-b", "localPath" => repo_b_path})

    assert_public_hygiene(repo_a_response, [repo_a_path, repo_b_path, data_dir])
    assert_public_hygiene(repo_b_response, [repo_a_path, repo_b_path, data_dir])

    repo_a = repo_a_response["repo"]
    repo_b = repo_b_response["repo"]
    repo_a_id = repo_a["repoId"]
    repo_b_id = repo_b["repoId"]

    placement =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/registry/repos/#{repo_a_id}/placement", %{
        "primaryNodeId" => "node_local",
        "mirrorNodeIds" => ["node_mirror"],
        "readPolicy" => "primary_or_mirror",
        "writePolicy" => "primary_only",
        "migrationState" => "stable"
      })
      |> json!(200)

    assert placement["placement"]["primaryNodeId"] == "node_local"

    mirror =
      create_mirror!(build_conn(), token, repo_a_id, %{
        "targetNodeId" => "node_mirror",
        "status" => "pending"
      })

    assert mirror["mirror"]["targetNodeId"] == "node_mirror"

    whoami =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/auth/whoami")
      |> json!(200)

    assert whoami["authenticated"] == true
    assert whoami["principal"]["actorId"] == "actor_demo"

    scope_body =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/policy/effective-scope", %{"repoId" => repo_a_id})
      |> json!(200)

    scope = scope_body["effectiveScope"]
    assert "workspace:create" in scope["capabilities"]
    assert "graph:query" in scope["capabilities"]
    assert "snapshot:build" in scope["capabilities"]

    node =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/node")
      |> json!(200)

    assert node["node"]["id"] == "node_local"

    resolved_placement =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/registry/repos/#{repo_a_id}/placement")
      |> json!(200)

    assert resolved_placement["placement"]["mirrorNodeIds"] == ["node_mirror"]

    workspace =
      create_workspace!(build_conn(), token, repo_a_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/phase10",
        "mode" => "writable",
        "allowedPaths" => ["docs/**", "src/content/**", "plain/**", "package.json"]
      })

    workspace_id = workspace["workspaceId"]
    assert is_binary(workspace["baseCommitSha"])

    assert workspace["effectiveScope"]["paths"] == [
             "docs/**",
             "src/content/**",
             "plain/**",
             "package.json"
           ]

    refute inspect(workspace) =~ "materializedPath"

    search =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/files/search", %{
        "paths" => ["docs/**", "src/content/**", "plain/**"],
        "query" => "phase ten provenance",
        "limit" => 20
      })
      |> json!(200)

    assert Enum.any?(search["results"], &(&1["path"] == "docs/readme.md"))

    graph_refresh =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/graph/refresh", %{
        "ref" => "refs/heads/main",
        "paths" => ["docs/**", "src/content/**", "plain/**"]
      })
      |> json!(200)

    assert graph_refresh["ready"] == true

    assert graph_refresh["snapshotRoot"] ==
             "treedb://graph/#{repo_a_id}/#{graph_refresh["graphVersion"]}"

    context =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/context/build", %{
        "ref" => "refs/heads/main",
        "query" => "phase ten provenance",
        "scope" => "sections",
        "options" => %{"limit" => 8, "depth" => 1},
        "budget" => %{"maxNodes" => 8, "maxTokens" => 1800}
      })
      |> json!(200)

    assert is_list(context["nodes"])
    assert is_integer(context["totalTokenEstimate"])

    limited_token = limited_actor_token!(repo_a_id)

    federation_plan =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/federation/query/plan", %{
        "repoIds" => [repo_a_id, repo_b_id],
        "refs" => %{repo_a_id => "refs/heads/main", repo_b_id => "refs/heads/main"},
        "paths" => %{repo_a_id => ["docs/**", "src/content/**"], repo_b_id => ["**"]},
        "queryType" => "text",
        "capabilities" => ["files:search"]
      })
      |> json!(200)

    allowed = federation_plan["effectiveScope"]["repos"]
    assert [%{"repoId" => ^repo_a_id, "paths" => ["docs/**"]}] = allowed
    assert Enum.any?(federation_plan["rejected"], &(&1["repoId"] == repo_b_id))
    refute Jason.encode!(federation_plan) =~ "phase ten provenance"
    refute Jason.encode!(federation_plan) =~ "docs/private/hidden.md"
    refute Jason.encode!(federation_plan) =~ "src/content/notes"

    updated_content = """
    ---
    title: Phase Ten Readme
    status: published
    tags:
      - phase10
      - provenance
    updated_at: 2026-06-02T00:00:00Z
    ---
    # Phase Ten Update

    The committed phase ten update is visible after commit.

    See [Guide](guide.md).
    """

    write =
      build_conn()
      |> auth_conn(token)
      |> put("/api/v1/workspaces/#{workspace_id}/files?path=docs/readme.md", %{
        "content" => updated_content
      })
      |> json!(200)

    assert write["file"]["path"] == "docs/readme.md"

    read_only_exec =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "mode" => "read_only",
        "cmd" => "rg phase docs plain src/content",
        "maxOutputBytes" => 10_000
      })
      |> json!(200)

    assert read_only_exec["exitCode"] == 0
    assert read_only_exec["changedPaths"] == []

    verify_exec =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "mode" => "verification",
        "cmd" => "npm test"
      })
      |> json!(200)

    assert verify_exec["exitCode"] == 0

    status =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/status")
      |> json!(200)

    assert Enum.any?(status["changes"], &(&1["path"] == "docs/readme.md"))

    diff =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/diff")
      |> json!(200)

    assert "docs/readme.md" in diff["changedPaths"]
    assert diff["diff"] =~ "committed phase ten update"

    commit =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/commit", %{
        "message" => "Phase 10 update",
        "author" => %{"name" => "TreeDB Agent", "email" => "agent@example.invalid"}
      })
      |> json!(200)

    branch_name = commit["branchName"]
    assert commit["status"] == "committed"
    assert is_binary(commit["commitSha"])
    assert "docs/readme.md" in commit["changedPaths"]

    committed_read =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/files/read", %{
        "ref" => branch_name,
        "path" => "docs/readme.md",
        "parseFrontmatter" => true
      })
      |> json!(200)

    assert committed_read["file"]["body"] =~ "committed phase ten update"

    committed_graph =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/graph/refresh", %{
        "ref" => branch_name,
        "paths" => ["docs/**", "src/content/**", "plain/**"]
      })
      |> json!(200)

    assert committed_graph["ready"] == true

    graph_search =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/graph/search-sections", %{
        "ref" => branch_name,
        "query" => "committed phase ten update",
        "limit" => 20
      })
      |> json!(200)

    assert Enum.any?(graph_search["results"], &(get_in(&1, ["node", "path"]) == "docs/readme.md"))

    snapshot =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/snapshots/build", %{
        "ref" => branch_name,
        "kind" => "repository_snapshot",
        "paths" => ["docs/**", "src/content/**"],
        "includeGraph" => true
      })
      |> json!(200)
      |> Map.fetch!("snapshot")

    assert is_binary(snapshot["snapshotId"])
    assert is_binary(snapshot["commitSha"])
    assert snapshot["kind"] == "repository_snapshot"
    assert snapshot["includedPaths"] == ["docs/**", "src/content/**"]
    assert snapshot["graphVersion"] == committed_graph["graphVersion"]
    assert snapshot["artifact"]["format"] == "tar.zst"

    artifact =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/artifacts/export", %{
        "snapshotId" => snapshot["snapshotId"]
      })
      |> json!(200)
      |> Map.fetch!("artifact")

    assert artifact["snapshotId"] == snapshot["snapshotId"]
    assert artifact["uri"] == "treedb://artifact/#{snapshot["snapshotId"]}"

    migration =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_a_id}/migrations", %{
        "targetNodeId" => "node_mirror",
        "sourceNodeId" => "node_local",
        "mode" => "primary_transfer",
        "dryRun" => true,
        "requireMirrorSynced" => false
      })
      |> json!(200)

    assert migration["migration"]["status"] == "planned"

    placement_after_migration =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/registry/repos/#{repo_a_id}/placement")
      |> json!(200)

    assert placement_after_migration["placement"]["primaryNodeId"] == "node_local"

    audit =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/audit/events", %{"repoId" => repo_a_id, "limit" => 200})
      |> json!(200)

    event_types = Enum.map(audit["events"], & &1["eventType"])
    assert_event(event_types, ["repo.registered"])
    assert_event(event_types, ["workspace.created"])
    assert_event(event_types, ["file.written"])
    assert_event(event_types, ["exec.completed", "workspace.exec_completed"])
    assert_event(event_types, ["git.commit.created", "workspace.committed"])
    assert_event(event_types, ["graph.refresh.completed", "graph.refreshed"])
    assert_event(event_types, ["snapshot.built"])
    assert_event(event_types, ["artifact.exported"])
    assert_event(event_types, ["migration.created"])

    audit_json = Jason.encode!(audit)
    refute audit_json =~ "committed phase ten update"
    refute audit_json =~ "stdout"
    refute audit_json =~ repo_a_path
    refute audit_json =~ data_dir

    [
      repo_a_response,
      repo_b_response,
      placement,
      mirror,
      whoami,
      scope_body,
      node,
      resolved_placement,
      workspace,
      search,
      graph_refresh,
      context,
      federation_plan,
      write,
      read_only_exec,
      verify_exec,
      status,
      diff,
      commit,
      committed_read,
      committed_graph,
      graph_search,
      %{"snapshot" => snapshot},
      %{"artifact" => artifact},
      migration,
      audit
    ]
    |> Enum.each(&assert_public_hygiene(&1, [repo_a_path, repo_b_path, data_dir]))

    TreeDb.Store.init!(node_id: "node_local")

    assert {:ok, %{"id" => ^repo_a_id}} = TreeDb.Store.get_repository(repo_a_id)

    assert {:ok, %{"repositoryId" => ^repo_a_id}} =
             TreeDb.Store.get_repository_placement(repo_a_id)

    assert {:ok, events} = TreeDb.Store.list_audit_events(%{repoId: repo_a_id, limit: 200})
    assert length(events) > 0

    assert {:ok, %{"graphVersion" => _}} =
             TreeDb.Graph.Native.read_latest_graph_manifest(repo_a_id, branch_name)

    assert {:ok, %{"snapshotId" => snapshot_id}} =
             TreeDb.Store.get_snapshot_manifest(snapshot["snapshotId"])

    assert snapshot_id == snapshot["snapshotId"]
  end

  defp limited_actor_token!(repo_a_id) do
    {:ok, _grant} =
      TreeDb.Capabilities.put_grant(%{
        "actorId" => "actor_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_a_id],
        "capabilities" => ["files:search", "files:read", "graph:query", "query:federated"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"]
      })

    dev_token!(build_conn(), %{"actorId" => "actor_limited", "tenantId" => "tenant_demo"})
  end

  defp assert_event(event_types, aliases) do
    assert Enum.any?(aliases, &(&1 in event_types)),
           "expected one of #{inspect(aliases)} in #{inspect(event_types)}"
  end

  defp assert_public_hygiene(payload, forbidden_paths) do
    json = Jason.encode!(payload)
    refute json =~ "localPath"
    refute json =~ "materializedPath"
    refute json =~ "/var/lib/treedb"

    for path <- forbidden_paths do
      refute json =~ path
    end
  end
end
