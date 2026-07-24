defmodule TreeDxWeb.BlobControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
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
    assert get_resp_header(download, "x-treedx-content-hash") == [write["result"]["contentHash"]]
    assert get_resp_header(download, "x-treedx-source") == ["workspace"]

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

  test "multipart upload completes through workspace blob storage", %{
    token: token,
    workspace_id: workspace_id
  } do
    create =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/uploads", %{
        "path" => "assets/multipart.bin",
        "contentType" => "application/octet-stream"
      })
      |> json!(200)

    upload_id = create["upload"]["uploadId"]
    assert create["upload"]["status"] == "open"

    part1 =
      build_conn()
      |> auth_conn(token)
      |> put_req_header("content-type", "application/octet-stream")
      |> put("/api/v1/workspaces/#{workspace_id}/blobs/uploads/#{upload_id}/parts/1", <<1, 2>>)
      |> json!(200)

    assert part1["part"]["byteLength"] == 2

    build_conn()
    |> auth_conn(token)
    |> put_req_header("content-type", "application/octet-stream")
    |> put("/api/v1/workspaces/#{workspace_id}/blobs/uploads/#{upload_id}/parts/2", <<3, 4>>)
    |> json!(200)

    complete =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/uploads/#{upload_id}/complete", %{})
      |> json!(200)

    assert complete["upload"]["status"] == "completed"
    assert complete["result"]["path"] == "assets/multipart.bin"
    assert complete["result"]["byteLength"] == 4

    download =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/blobs/download?path=assets/multipart.bin")

    assert response(download, 200) == <<1, 2, 3, 4>>
    assert_public_hygiene!(Map.delete(complete, "result"))
  end

  test "multipart upload abort marks the session without committing", %{
    token: token,
    workspace_id: workspace_id
  } do
    upload =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/uploads", %{
        "path" => "assets/aborted.bin"
      })
      |> json!(200)

    upload_id = upload["upload"]["uploadId"]

    abort =
      build_conn()
      |> auth_conn(token)
      |> delete("/api/v1/workspaces/#{workspace_id}/blobs/uploads/#{upload_id}")
      |> json!(200)

    assert abort["upload"]["status"] == "aborted"

    read =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/blobs/download?path=assets/aborted.bin")
      |> json!(404)

    assert read["error"]["code"] == "not_found"
  end

  test "workspace status and diff expose binary metadata without payload", %{
    token: token,
    workspace_id: workspace_id
  } do
    content = <<0, 159, 146, 150, 255>>

    write =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/blobs/write", %{
        "path" => "assets/status.bin",
        "encoding" => "base64",
        "contentBase64" => Base.encode64(content)
      })
      |> json!(200)

    status =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/status")
      |> json!(200)

    entry = Enum.find(status["changes"], &(&1["path"] == "assets/status.bin"))
    assert entry["binary"] == true
    assert entry["encoding"] == "base64"
    assert entry["contentHash"] == write["result"]["contentHash"]
    refute Jason.encode!(status) =~ Base.encode64(content)
    assert_public_hygiene!(status)

    diff =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/diff")
      |> json!(200)

    assert diff["diff"] =~ "Binary file assets/status.bin added"
    refute diff["diff"] =~ Base.encode64(content)
    assert_public_hygiene!(diff)
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

    previous = System.get_env("TREEDX_MAX_BLOB_BYTES")
    System.put_env("TREEDX_MAX_BLOB_BYTES", "3")

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
        do: System.put_env("TREEDX_MAX_BLOB_BYTES", previous),
        else: System.delete_env("TREEDX_MAX_BLOB_BYTES")
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
      TreeDx.Capabilities.put_grant(%{
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
