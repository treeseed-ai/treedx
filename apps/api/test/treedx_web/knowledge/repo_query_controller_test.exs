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
    TreeDx.RepositoryCache.reset!()

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
    assert file["frontmatter"]["tags"] == ["release", "documentation"]
    assert file["frontmatter"]["metadata"]["nested"] == true
    assert file["body"] =~ "release provenance"
    refute Map.has_key?(json_response(conn, 200), "localPath")

    cache_keys = :ets.tab2list(TreeDx.RepositoryCache) |> Enum.map(&elem(&1, 0))
    assert {:repository_context, repo_id, :default} in cache_keys
    assert {:authorization_scope, "actor_demo", repo_id} in cache_keys
    assert Enum.any?(cache_keys, &match?({{:document, "docs/readme.md", _, _}, _, _, _, _}, &1))
    refute Enum.any?(cache_keys, &match?({kind, _, _, _, _} when kind in [:tree, :documents], &1))

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

  test "parses structured CRLF frontmatter and reports malformed frontmatter", %{
    token: token,
    repo_id: repo_id
  } do
    structured =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/structured.md",
        "parseFrontmatter" => true
      })
      |> json_response(200)
      |> Map.fetch!("file")

    assert structured["frontmatter"]["relations"] == [%{"id" => "page.child", "weight" => 2}]
    assert structured["frontmatter"]["tags"] == ["security", "teams"]
    assert structured["body"] == "# Structured\r\n"
    assert structured["frontmatterError"] == nil

    malformed =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/malformed.md",
        "parseFrontmatter" => true
      })
      |> json_response(200)
      |> Map.fetch!("file")

    assert malformed["frontmatter"] == %{}
    assert malformed["frontmatterError"]["code"] == "invalid_frontmatter"
  end

  test "pages bounded repository reads without splitting UTF-8", %{
    token: token,
    repo_id: repo_id
  } do
    first =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/readme.md",
        "maxBytes" => 24
      })
      |> json_response(200)
      |> Map.fetch!("file")

    assert first["offsetBytes"] == 0
    assert first["returnedBytes"] <= 24
    assert first["contentBytes"] == first["size"]
    assert first["truncated"] == true
    assert is_integer(first["nextOffsetBytes"])
    assert first["body"] == nil

    second =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "path" => "docs/readme.md",
        "maxBytes" => 24,
        "offsetBytes" => first["nextOffsetBytes"]
      })
      |> json_response(200)
      |> Map.fetch!("file")

    assert second["offsetBytes"] == first["nextOffsetBytes"]
    assert String.valid?(second["content"])
    refute second["content"] == first["content"]

    invalid =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{
        "paths" => ["docs/readme.md", "docs/page.mdx"],
        "maxBytes" => 24
      })

    assert json_response(invalid, 422)["error"]["code"] == "validation_error"
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

  test "connected JWT path scope narrows broader repository grants", %{repo_id: repo_id} do
    old_auth = System.get_env("TREEDX_AUTH_MODE")
    old_issuer = System.get_env("TREEDX_JWT_ISSUER")
    old_audience = System.get_env("TREEDX_JWT_AUDIENCE")
    old_secret = System.get_env("TREEDX_JWT_HS256_SECRET")

    System.put_env("TREEDX_AUTH_MODE", "connected")
    System.put_env("TREEDX_JWT_ISSUER", "https://issuer.example.invalid")
    System.put_env("TREEDX_JWT_AUDIENCE", "treedx")
    System.put_env("TREEDX_JWT_HS256_SECRET", "test-secret")

    on_exit(fn ->
      restore_env("TREEDX_AUTH_MODE", old_auth)
      restore_env("TREEDX_JWT_ISSUER", old_issuer)
      restore_env("TREEDX_JWT_AUDIENCE", old_audience)
      restore_env("TREEDX_JWT_HS256_SECRET", old_secret)
    end)

    token =
      jwt(%{
        "iss" => "https://issuer.example.invalid",
        "aud" => "treedx",
        "sub" => "actor_demo",
        "treedx_actor_id" => "actor_demo",
        "treedx_tenant_id" => "tenant_demo",
        "treedx_repo_ids" => [repo_id],
        "treedx_capabilities" => ["files:read"],
        "treedx_refs" => ["*"],
        "treedx_paths" => ["docs/**"],
        "exp" => System.system_time(:second) + 3600,
        "jti" => "repo_query_connected_scope_test"
      })

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/paths/list", %{"paths" => ["**"]})

    paths = json_response(conn, 200)["entries"] |> Enum.map(& &1["path"])
    assert "docs/readme.md" in paths
    assert "docs/page.mdx" in paths
    refute "outside.md" in paths

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => "docs/readme.md"})

    assert json_response(conn, 200)["file"]["path"] == "docs/readme.md"

    conn =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/files/read", %{"path" => "outside.md"})

    assert json_response(conn, 403)["error"]["code"] == "permission_denied"
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp jwt(payload) do
    header = %{"alg" => "HS256", "typ" => "JWT"} |> Jason.encode!() |> b64()
    body = payload |> Jason.encode!() |> b64()
    signature = :crypto.mac(:hmac, :sha256, "test-secret", "#{header}.#{body}") |> b64()
    "#{header}.#{body}.#{signature}"
  end

  defp b64(bytes), do: Base.url_encode64(bytes, padding: false)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

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
      - documentation
    metadata:
      nested: true
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

    File.write!(
      Path.join(path, "docs/structured.md"),
      "\uFEFF---\r\ntitle: Structured\r\ntags: [security, teams]\r\nrelations:\r\n  - id: page.child\r\n    weight: 2\r\n---\r\n# Structured\r\n"
    )

    File.write!(Path.join(path, "docs/malformed.md"), "---\ntags: [broken\n---\nBody\n")

    File.write!(Path.join(path, ".env"), "SECRET=true\n")
    File.write!(Path.join(path, "outside.md"), "outside docs scope\n")
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
