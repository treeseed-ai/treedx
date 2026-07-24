defmodule TreeDxWeb.ExecSandboxTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/exec-sandbox")
    create_git_repo!(repo_path)
    token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "exec-sandbox",
        "localPath" => repo_path
      })["repo"]

    workspace =
      create_workspace!(build_conn(), token, repo["repoId"], %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/exec-sandbox",
        "mode" => "writable",
        "allowedPaths" => ["docs/**"]
      })

    {:ok, token: token, repo_id: repo["repoId"], workspace_id: workspace["workspaceId"]}
  end

  test "direct_dev is rejected in connected mode" do
    previous_mode = System.get_env("TREEDX_AUTH_MODE")
    previous_backend = System.get_env("TREEDX_EXEC_BACKEND")
    previous_allow = System.get_env("TREEDX_ALLOW_DIRECT_EXEC_IN_PROD")
    System.put_env("TREEDX_AUTH_MODE", "connected")
    System.put_env("TREEDX_EXEC_BACKEND", "direct_dev")
    System.delete_env("TREEDX_ALLOW_DIRECT_EXEC_IN_PROD")

    try do
      assert {:error, %{code: "sandbox_policy_denied"}} =
               TreeDx.Exec.Backend.run("true", System.tmp_dir!(), 1000, 1000, %{})
    after
      restore_env("TREEDX_AUTH_MODE", previous_mode)
      restore_env("TREEDX_EXEC_BACKEND", previous_backend)
      restore_env("TREEDX_ALLOW_DIRECT_EXEC_IN_PROD", previous_allow)
    end
  end

  test "container sandbox command builder disables network and applies resource limits" do
    {args, sandbox} =
      TreeDx.Exec.Backends.ContainerSandbox.docker_args(
        "/tmp/workspace",
        "/tmp/run",
        "/tmp/run/command.sh",
        5_000,
        "none",
        %{"resourceLimits" => %{"cpu" => 2, "memoryMb" => 1024, "pids" => 128}}
      )

    assert "--network" in args
    assert "none" in args
    assert "--read-only" in args
    assert sandbox.isolated == true
    assert sandbox.backend == "container_sandbox"
    assert sandbox.resourceLimits.cpu == 1
    assert sandbox.resourceLimits.memoryMb == 512
    assert sandbox.resourceLimits.pids == 64
  end

  test "container sandbox reports unavailable when docker cannot be found" do
    previous_backend = System.get_env("TREEDX_EXEC_BACKEND")
    previous_path = System.get_env("PATH")
    System.put_env("TREEDX_EXEC_BACKEND", "container_sandbox")
    System.put_env("PATH", "")

    try do
      assert {:error, %{code: "sandbox_unavailable"}} =
               TreeDx.Exec.Runner.run("true", System.tmp_dir!(), 1000, 1000, %{})
    after
      restore_env("TREEDX_EXEC_BACKEND", previous_backend)
      restore_env("PATH", previous_path)
    end
  end

  test "write-limited exec persists binary changes as blob overlays", %{
    token: token,
    workspace_id: workspace_id
  } do
    response =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/workspaces/#{workspace_id}/exec", %{
        "cmd" => "printf '\\377' > docs/binary.bin",
        "mode" => "write_limited"
      })
      |> json!(200)

    assert response["exitCode"] == 0
    assert response["sandbox"]["backend"] == "direct_dev"
    assert response["changedPaths"] == ["docs/binary.bin"]

    status =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/workspaces/#{workspace_id}/status")
      |> json!(200)

    entry = Enum.find(status["changes"], &(&1["path"] == "docs/binary.bin"))
    assert entry["binary"] == true
    assert entry["encoding"] == "base64"
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
