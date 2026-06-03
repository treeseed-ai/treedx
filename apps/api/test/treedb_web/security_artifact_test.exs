defmodule TreeDbWeb.SecurityArtifactTest do
  use TreeDbWeb.ConnCase, async: false

  test "artifact routes require authorization and sanitize identifiers", %{conn: conn} do
    token = dev_token!(conn)
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/security-artifacts")
    create_git_repo!(repo_path)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "security-artifacts",
        "localPath" => repo_path
      })["repo"]

    build_conn()
    |> post("/api/v1/repos/#{repo["repoId"]}/snapshots/build", %{"paths" => ["docs/**"]})
    |> json_response(401)

    snapshot =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo["repoId"]}/snapshots/build", %{"paths" => ["docs/**"]})
      |> json!(200)

    artifact =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo["repoId"]}/artifacts/export", %{
        "snapshotId" => snapshot["snapshot"]["snapshotId"]
      })
      |> json!(200)

    assert artifact["artifact"]["uri"] =~ "treedb://artifact/"
    assert_public_hygiene!(artifact)

    traversal =
      build_conn()
      |> auth_conn(token)
      |> get(
        "/api/v1/repos/#{repo["repoId"]}/artifacts/#{URI.encode("../secret", &URI.char_unreserved?/1)}"
      )
      |> json_response(404)

    assert traversal["error"]["code"] == "not_found"
    assert_public_hygiene!(traversal)
  end
end
