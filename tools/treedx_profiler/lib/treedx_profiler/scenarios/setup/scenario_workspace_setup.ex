defmodule TreeDxProfiler.ScenarioWorkspaceSetup do
  @moduledoc false

  import TreeDxProfiler.ScenarioHttp,
    only: [
      assert_binary_or_ok: 1,
      assert_ok: 1,
      assert_ok_or_not_found: 1,
      assert_path: 2,
      assert_truthy: 2,
      call: 7,
      call!: 7,
      call!: 8
    ]

  def mutate_workspace(state) do
    ws = state.workspace_id
    content = "# Profiler Update\n\nrelease provenance updated through workspace\n"
    patch = "+++\n# Profiler Patch\n\nrelease patched through workspace\n"
    blob = Base.encode64("profiler binary payload #{state.opts.profile_id}")

    {state, _} =
      call(
        state,
        :put,
        "/api/v1/workspaces/#{ws}/files?path=docs/profiler-update.md",
        "writeWorkspaceFile",
        "workspace",
        %{"content" => content},
        expected: 200,
        assert: fn payload -> assert_path(payload, "docs/profiler-update.md") end
      )

    state
    |> call!(
      :put,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-delete.md",
      "writeWorkspaceFile",
      "workspace",
      %{"content" => "release delete target #{state.opts.profile_id}\n"},
      &assert_ok/1
    )
    |> call!(
      :patch,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-patch.md",
      "patchWorkspaceFile",
      "workspace",
      %{"content" => patch},
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
    |> maybe_delete_workspace_file()
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/files?path=docs/profiler-update.md",
      "readWorkspaceFile",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/search",
      "searchWorkspace",
      "workspace",
      %{"query" => "release", "paths" => ["docs/**"]},
      &assert_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/blobs/write",
      "writeWorkspaceBlob",
      "blob",
      %{
        "path" => "assets/profiler.bin",
        "encoding" => "base64",
        "contentBase64" => blob,
        "contentType" => "application/octet-stream"
      },
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/blobs/download?path=assets/profiler.bin",
      "downloadWorkspaceBlob",
      "blob",
      nil,
      &assert_binary_or_ok/1
    )
    |> call!(
      :post,
      "/api/v1/workspaces/#{ws}/blobs/delete",
      "deleteWorkspaceBlob",
      "blob",
      %{"path" => "assets/profiler-deleted.bin"},
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
    |> call!(
      :put,
      "/api/v1/workspaces/#{ws}/blobs/upload?path=assets/direct-upload.bin",
      "uploadWorkspaceBlob",
      "blob",
      "direct upload payload #{state.opts.profile_id}",
      &assert_ok/1,
      headers: [{"content-type", "application/octet-stream"}]
    )
    |> abort_multipart_upload()
    |> multipart_roundtrip()
    |> maybe_exec_workspace()
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/status",
      "getWorkspaceStatus",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> call!(
      :get,
      "/api/v1/workspaces/#{ws}/diff",
      "getWorkspaceDiff",
      "workspace",
      nil,
      &assert_ok/1
    )
    |> commit_workspace()
  end

  defp maybe_delete_workspace_file(%{opts: %{include_destructive: true}} = state) do
    call!(
      state,
      :delete,
      "/api/v1/workspaces/#{state.workspace_id}/files?path=docs/profiler-delete.md",
      "deleteWorkspaceFile",
      "workspace",
      nil,
      &assert_ok_or_not_found/1,
      expected: [200, 404]
    )
  end

  defp maybe_delete_workspace_file(state), do: state

  defp maybe_exec_workspace(%{opts: %{include_exec: true}} = state) do
    call!(
      state,
      :post,
      "/api/v1/workspaces/#{state.workspace_id}/exec",
      "execWorkspace",
      "exec",
      %{
        "mode" => "read_only",
        "cmd" => "pwd",
        "timeoutMs" => 10_000,
        "maxOutputBytes" => 4096
      },
      &assert_ok/1
    )
  end

  defp maybe_exec_workspace(state), do: state

  defp multipart_roundtrip(state) do
    ws = state.workspace_id
    payload = "multipart profiler payload #{state.opts.profile_id}"

    {state, create} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads",
        "createWorkspaceBlobUpload",
        "blob",
        %{
          "path" => "assets/multipart.txt",
          "contentType" => "text/plain",
          "expectedByteLength" => byte_size(payload)
        },
        expected: [200, 201],
        assert: &assert_ok/1
      )

    upload_id =
      get_in(create, ["upload", "uploadId"]) || get_in(create, ["session", "uploadId"]) ||
        create["uploadId"]

    if upload_id do
      state
      |> call!(
        :put,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}/parts/1",
        "uploadWorkspaceBlobPart",
        "blob",
        payload,
        &assert_ok/1,
        headers: [{"content-type", "application/octet-stream"}]
      )
      |> call!(
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}/complete",
        "completeWorkspaceBlobUpload",
        "blob",
        %{},
        &assert_ok/1
      )
    else
      state
    end
  end

  defp abort_multipart_upload(state) do
    ws = state.workspace_id

    {state, create} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/blobs/uploads",
        "createWorkspaceBlobUpload",
        "blob",
        %{
          "path" => "assets/aborted-upload.txt",
          "contentType" => "text/plain",
          "expectedByteLength" => 24
        },
        expected: [200, 201],
        assert: &assert_ok/1
      )

    upload_id =
      get_in(create, ["upload", "uploadId"]) || get_in(create, ["session", "uploadId"]) ||
        create["uploadId"]

    if upload_id do
      call!(
        state,
        :delete,
        "/api/v1/workspaces/#{ws}/blobs/uploads/#{upload_id}",
        "abortWorkspaceBlobUpload",
        "blob",
        nil,
        &assert_ok/1
      )
    else
      state
    end
  end

  defp commit_workspace(state) do
    ws = state.workspace_id

    {state, response} =
      call(
        state,
        :post,
        "/api/v1/workspaces/#{ws}/commit",
        "commitWorkspace",
        "workspace",
        %{
          "message" => "Profiler update",
          "author" => %{"name" => "TreeDX Profiler", "email" => "profiler@example.invalid"}
        },
        expected: 200,
        assert: fn payload -> assert_truthy(payload["commitSha"], "commit sha") end
      )

    Map.put(
      state,
      :branch_name,
      response["branchName"] || "refs/heads/profiler/#{state.opts.profile_id}"
    )
  end
end
