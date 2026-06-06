defmodule TreeDxWeb.RepoQueryControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/repo-query")
    create_query_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "repo-query", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    {:ok, token: token, repo_id: repo_id}
  end

  test "reads, lists, searches, queries, and compares repository content", %{
    token: token,
    repo_id: repo_id
  } do
    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/readme.md",
        "parseFrontmatter" => true
      })

    file = json_response(conn, 200)["file"]
    assert file["frontmatter"]["title"] == "Read Me"
    assert file["frontmatter"]["status"] == "published"
    assert file["body"] =~ "release provenance"
    refute Map.has_key?(json_response(conn, 200), "localPath")

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/paths/list", %{
        "paths" => ["docs/**"],
        "extensions" => [".md", ".mdx"]
      })

    paths = json_response(conn, 200)["entries"] |> Enum.map(& &1["path"])
    assert "docs/readme.md" in paths
    assert "docs/page.mdx" in paths
    refute ".env" in paths

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/search", %{
        "paths" => ["docs/**"],
        "query" => "release provenance",
        "filters" => [%{"field" => "status", "op" => "eq", "value" => "published"}],
        "sort" => [%{"field" => "path", "direction" => "asc"}],
        "limit" => 20
      })

    results = json_response(conn, 200)["results"]
    assert Enum.any?(results, &(&1["path"] == "docs/readme.md"))
    assert Enum.all?(results, &String.starts_with?(&1["path"], "docs/"))

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/query", %{
        "type" => "section",
        "paths" => ["docs/**"],
        "query" => "Overview"
      })

    assert Enum.any?(json_response(conn, 200)["results"], &(&1["heading"] == "Overview"))

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/query", %{
        "type" => "link",
        "paths" => ["docs/**"],
        "query" => "guide"
      })

    assert Enum.any?(json_response(conn, 200)["results"], &(&1["target"] == "../guide.md"))

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/query", %{
        "type" => "changed_path",
        "ref" => "refs/heads/feature",
        "baseRef" => "refs/heads/main",
        "paths" => ["docs/**"]
      })

    changes = json_response(conn, 200)["results"]
    assert Enum.any?(changes, &(&1["path"] == "docs/readme.md" and &1["status"] == "modified"))
    assert Enum.any?(changes, &(&1["path"] == "docs/new.md" and &1["status"] == "added"))
  end

  test "enforces auth, path policy, protected paths, and binary handling", %{
    token: token,
    repo_id: repo_id
  } do
    conn =
      build_conn()
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => "docs/readme.md"})

    assert json_response(conn, 401)["error"]["code"] == "authentication_required"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => "../secret"})

    assert json_response(conn, 422)["error"]["code"] == "validation_error"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => ".env"})

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/paths/list", %{"paths" => ["**"]})

    refute ".env" in (json_response(conn, 200)["entries"] |> Enum.map(& &1["path"]))

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => "docs/binary.dat"})

    assert json_response(conn, 415)["error"]["code"] == "unsupported_media_type"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/binary.dat",
        "encoding" => "base64"
      })

    assert json_response(conn, 200)["file"]["encoding"] == "base64"
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_query_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.mkdir_p!(Path.join(path, "docs"))

    File.write!(Path.join(path, "docs/readme.md"), """
    ---
    title: Read Me
    status: published
    updated_at: 2026-06-01T00:00:00Z
    tags:
      - release
      - provenance
    ---
    # Overview

    This release provenance document links to [Guide](../guide.md).
    """)

    File.write!(Path.join(path, "docs/page.mdx"), """
    ---
    title: Page
    status: draft
    ---
    import Widget from './widget'

    # Page
    """)

    File.write!(Path.join(path, ".env"), "SECRET=true\n")
    File.write!(Path.join(path, "docs/binary.dat"), <<255, 0, 1>>)
    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
    git(path, ["checkout", "-b", "feature"])
    File.write!(Path.join(path, "docs/readme.md"), "# Overview\n\nupdated release provenance\n")
    File.write!(Path.join(path, "docs/new.md"), "new file\n")
    git(path, ["add", "-A"])
    git(path, ["commit", "-m", "feature"])
    git(path, ["checkout", "main"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
