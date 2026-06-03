defmodule TreeDbWeb.BlobControllerTest do
  use TreeDbWeb.ConnCase, async: false

  setup %{conn: conn} do
    data_dir = TreeDb.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/blob-api-repo")
    create_git_repo!(repo_path)
    File.mkdir_p!(Path.join(repo_path, "assets"))
    binary = <<0, 159, 146, 150, 255>>
    File.write!(Path.join(repo_path, "assets/logo.bin"), binary)
    git!(repo_path, ["add", "assets/logo.bin"])
    git!(repo_path, ["commit", "-m", "Add binary fixture"])

    token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "blob-api-repo",
        "localPath" => repo_path
      })["repo"]

    workspace =
      create_workspace!(build_conn(), token, repo["repoId"], %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/blob-api",
        "mode" => "writable",
        "allowedPaths" => ["**"]
      })

    {:ok,
     token: token, repo_id: repo["repoId"], workspace_id: workspace["workspaceId"], binary: binary}
  end

  test "reads repository binary blob as base64", %{token: token, repo_id: repo_id, binary: binary} do
    response =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/blobs/read", %{
        "ref" => "refs/heads/main",
        "path" => "assets/logo.bin",
        "encoding" => "base64"
      })
      |> json!(200)

    assert response["blob"]["contentBase64"] == Base.encode64(binary)
    assert response["blob"]["byteLength"] == byte_size(binary)
    assert response["blob"]["contentType"] == "application/octet-stream"
    assert response["blob"]["contentHash"] =~ "blake3:"
    assert_public_hygiene!(Map.delete(response, "blob"))
  end

  test "writes, downloads, uploads, and deletes workspace blobs", %{
    token: token,
    workspace_id: workspace_id
  } do
    content = <<1, 2, 3, 4, 255>>

    write =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/write", %{
        "path" => "assets/new.bin",
        "encoding" => "base64",
        "contentBase64" => Base.encode64(content),
        "contentType" => "application/octet-stream"
      })
      |> json!(200)

    assert write["result"]["op"] == "put"
    assert write["result"]["contentHash"] =~ "blake3:"
    assert write["result"]["byteLength"] == byte_size(content)
    assert_public_hygiene!(write)

    download =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/blobs/download?path=assets/new.bin")

    assert response(download, 200) == content
    assert get_resp_header(download, "x-treedb-content-hash") == [write["result"]["contentHash"]]
    assert get_resp_header(download, "x-treedb-source") == ["workspace"]

    uploaded = <<9, 8, 7, 6>>

    upload =
      build_conn()
      |> auth_conn(token)
      |> put_req_header("content-type", "application/octet-stream")
      |> put("/api/v1/workspaces/#{workspace_id}/blobs/upload?path=assets/upload.bin", uploaded)
      |> json!(200)

    assert upload["result"]["byteLength"] == byte_size(uploaded)

    delete =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/delete", %{"path" => "assets/upload.bin"})
      |> json!(200)

    assert delete["result"]["op"] == "delete"
  end

  test "blob validation handles limits, malformed base64, and hash conflicts", %{
    token: token,
    workspace_id: workspace_id
  } do
    malformed =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/write", %{
        "path" => "assets/bad.bin",
        "contentBase64" => "not base64"
      })
      |> json!(422)

    assert malformed["error"]["code"] == "validation_error"

    mismatch =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/write", %{
        "path" => "assets/bad-hash.bin",
        "contentBase64" => Base.encode64(<<1, 2, 3>>),
        "expectedContentHash" => "blake3:bad"
      })
      |> json!(409)

    assert mismatch["error"]["code"] == "conflict"

    previous = System.get_env("TREEDB_MAX_BLOB_BYTES")
    System.put_env("TREEDB_MAX_BLOB_BYTES", "3")

    try do
      too_large =
        build_conn()
        |> auth_conn(token)
        |> post("/api/v1/workspaces/#{workspace_id}/blobs/write", %{
          "path" => "assets/large.bin",
          "contentBase64" => Base.encode64(<<1, 2, 3, 4>>)
        })
        |> json!(413)

      assert too_large["error"]["code"] == "payload_too_large"
    after
      if previous,
        do: System.put_env("TREEDB_MAX_BLOB_BYTES", previous),
        else: System.delete_env("TREEDB_MAX_BLOB_BYTES")
    end
  end

  test "blob path scopes and text API UTF-8 boundary are enforced", %{
    token: token,
    repo_id: repo_id,
    workspace_id: workspace_id
  } do
    text_read =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/files?path=assets/logo.bin")
      |> json!(415)

    assert text_read["error"]["code"] == "unsupported_media_type"

    {:ok, _grant} =
      TreeDb.Capabilities.put_grant(%{
        "actorId" => "actor_blob_limited",
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => [
          "repos:read",
          "repos:write",
          "workspace:create",
          "files:read",
          "files:write"
        ],
        "refs" => ["refs/heads/*"],
        "paths" => ["docs/**"]
      })

    limited_token =
      dev_token!(build_conn(), %{"actorId" => "actor_blob_limited", "tenantId" => "tenant_demo"})

    limited_workspace =
      create_workspace!(build_conn(), limited_token, repo_id, %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/blob-limited",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    denied =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/workspaces/#{limited_workspace["workspaceId"]}/blobs/write", %{
        "path" => "assets/hidden.bin",
        "contentBase64" => Base.encode64(<<1>>)
      })
      |> json!(403)

    assert denied["error"]["code"] == "permission_denied"
  end
end
