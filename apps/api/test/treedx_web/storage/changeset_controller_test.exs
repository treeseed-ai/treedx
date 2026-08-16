defmodule TreeDxWeb.ChangesetControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token = dev_token!(conn)
    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/changesets")
    create_git_repo!(repo_path)

    repo =
      register_repo!(build_conn(), token, %{"name" => "changesets", "localPath" => repo_path})

    workspace =
      create_workspace!(build_conn(), token, repo["repo"]["repoId"], %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/changeset",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"],
        "ttlSeconds" => 1800
      })

    {:ok, token: token, workspace: workspace}
  end

  test "atomically creates, updates, and deletes files and replays its receipt", context do
    readme = read(context, "docs/readme.md", 200)["content"]
    guide = read(context, "docs/guide.md", 200)["content"]

    patch =
      [
        replace_patch(
          "docs/readme.md",
          readme,
          String.replace(readme, "# MVP Provenance", "# Updated Provenance")
        ),
        create_patch("docs/new.md", "---\nid: new-entry\n---\nnew entry"),
        delete_patch("docs/guide.md", guide)
      ]
      |> Enum.join("\n")

    request = request(context.workspace, patch, "changeset-replay-001")
    first = apply_changeset(context, request, 200)
    replay = apply_changeset(context, request, 200)

    assert first["contract"] == "treedx.changeset/v1"
    assert first["changedPaths"] == ["docs/readme.md", "docs/new.md", "docs/guide.md"]
    assert replay["idempotentReplay"]
    assert replay["workspaceVersion"] == first["workspaceVersion"]
    refute Map.has_key?(first, "artifacts")

    assert read(context, "docs/new.md", 200)["content"] == "---\nid: new-entry\n---\nnew entry\n"
    assert read(context, "docs/readme.md", 200)["content"] =~ "# Updated Provenance"
    assert read(context, "docs/guide.md", 404)["error"]["code"] == "not_found"
  end

  test "rejects stale, tampered, unauthorized, and partially invalid bundles", context do
    valid_patch = create_patch("docs/allowed.md", "allowed")

    stale =
      request(context.workspace, valid_patch, "changeset-stale-001")
      |> Map.put("baseCommitSha", String.duplicate("0", 40))

    assert apply_changeset(context, stale, 409)["error"]["code"] == "conflict"

    tampered =
      request(context.workspace, valid_patch, "changeset-tampered-001")
      |> Map.put("patchSha256", String.duplicate("0", 64))

    assert apply_changeset(context, tampered, 409)["error"]["code"] == "conflict"

    bundle = valid_patch <> "\n" <> create_patch("private/blocked.md", "blocked")

    assert apply_changeset(
             context,
             request(context.workspace, bundle, "changeset-scope-001"),
             403
           )

    assert read(context, "docs/allowed.md", 404)["error"]["code"] == "not_found"

    mismatched_headers =
      valid_patch
      |> String.replace(
        "diff --git a/docs/allowed.md b/docs/allowed.md",
        "diff --git a/docs/other.md b/docs/other.md"
      )

    assert apply_changeset(
             context,
             request(context.workspace, mismatched_headers, "changeset-headers-001"),
             422
           )["error"]["code"] == "validation_error"
  end

  test "accepts bounded gzip transport and binds idempotency keys to patch digests", context do
    patch = create_patch("docs/compressed.md", "compressed")

    compressed = request(context.workspace, patch, "changeset-compressed-001")

    assert apply_gzip_changeset(context, compressed, 200)["patchSha256"] == digest(patch)

    conflict_patch = create_patch("docs/other.md", "other")

    conflict =
      request(context.workspace, conflict_patch, "changeset-compressed-001")
      |> Map.put(
        "expectedWorkspaceVersion",
        apply_gzip_changeset(context, compressed, 200)["workspaceVersion"]
      )

    assert apply_changeset(context, conflict, 409)["error"]["code"] == "idempotency_conflict"
  end

  defp request(workspace, patch, key) do
    %{
      "contract" => "treedx.changeset/v1",
      "baseCommitSha" => workspace["baseCommitSha"],
      "baseRef" => workspace["baseRef"],
      "expectedDestinationRefHead" => workspace["baseCommitSha"],
      "idempotencyKey" => key,
      "patch" => patch,
      "patchSha256" => digest(patch)
    }
  end

  defp create_patch(path, content) do
    lines = String.split(content, "\n", trim: false)

    "diff --git a/#{path} b/#{path}\nnew file mode 100644\n--- /dev/null\n+++ b/#{path}\n@@ -0,0 +1,#{length(lines)} @@\n" <>
      Enum.map_join(lines, "\n", &("+" <> &1))
  end

  defp replace_patch(path, before, resulting_content) do
    old_lines = String.split(before, "\n", trim: false)
    new_lines = String.split(resulting_content, "\n", trim: false)

    "diff --git a/#{path} b/#{path}\n--- a/#{path}\n+++ b/#{path}\n@@ -1,#{length(old_lines)} +1,#{length(new_lines)} @@\n" <>
      Enum.map_join(old_lines, "\n", &("-" <> &1)) <>
      "\n" <>
      Enum.map_join(new_lines, "\n", &("+" <> &1))
  end

  defp delete_patch(path, before) do
    old_lines = String.split(before, "\n", trim: false)

    "diff --git a/#{path} b/#{path}\ndeleted file mode 100644\n--- a/#{path}\n+++ /dev/null\n@@ -1,#{length(old_lines)} +0,0 @@\n" <>
      Enum.map_join(old_lines, "\n", &("-" <> &1))
  end

  defp apply_changeset(context, request, status) do
    build_conn()
    |> auth_conn(context.token)
    |> post("/api/v1/workspaces/#{context.workspace["workspaceId"]}/changesets", request)
    |> json_response(status)
  end

  defp apply_gzip_changeset(context, request, status) do
    build_conn()
    |> auth_conn(context.token)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("content-encoding", "gzip")
    |> post(
      "/api/v1/workspaces/#{context.workspace["workspaceId"]}/changesets",
      request |> Jason.encode!() |> :zlib.gzip()
    )
    |> json_response(status)
  end

  defp read(context, path, status) do
    build_conn()
    |> auth_conn(context.token)
    |> get("/api/v1/workspaces/#{context.workspace["workspaceId"]}/files?path=#{path}")
    |> json_response(status)
  end

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
