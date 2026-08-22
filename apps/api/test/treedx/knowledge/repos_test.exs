defmodule TreeDx.ReposTest do
  use ExUnit.Case, async: false

  setup do
    dir = Path.join(System.tmp_dir!(), "treedx-repos-test-#{System.unique_integer([:positive])}")
    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")
    {:ok, principal: %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}, dir: dir}
  end

  test "effective scope returns dev capabilities", %{principal: principal} do
    {:ok, scope} = TreeDx.Capabilities.effective_scope(principal)
    assert "repos:write" in scope["capabilities"]
  end

  test "connected tokens narrow wildcard grants without losing repository and ref access" do
    {:ok, _grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => "gateway",
        "tenantId" => "control-plane",
        "repoIds" => ["*"],
        "refs" => ["*"],
        "paths" => ["**"],
        "capabilities" => ["repos:read", "files:read"]
      })

    principal = %{
      "actorId" => "gateway",
      "tenantId" => "control-plane",
      "authMode" => "connected",
      "tokenScope" => %{
        "repoIds" => ["repo_one"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/src/content/**"],
        "capabilities" => ["files:read"]
      }
    }

    assert {:ok, scope} = TreeDx.Capabilities.effective_scope(principal, "repo_one")
    assert scope["repoIds"] == ["repo_one"]
    assert scope["refs"] == ["refs/heads/main"]
    assert scope["paths"] == ["docs/src/content/**"]
    assert scope["capabilities"] == ["files:read"]
  end

  test "capability updates invalidate a cached authorization scope immediately" do
    actor_id = "cached-policy-actor"

    {:ok, grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => actor_id,
        "tenantId" => "tenant_demo",
        "repoIds" => ["repo_one"],
        "refs" => ["refs/heads/main"],
        "paths" => ["docs/**"],
        "capabilities" => ["files:read"]
      })

    principal = %{"actorId" => actor_id, "tenantId" => "tenant_demo"}
    assert {:ok, scope} = TreeDx.Capabilities.effective_scope(principal, "repo_one")
    assert "files:read" in scope["capabilities"]

    {:ok, _revoked} =
      grant
      |> Map.put("revokedAt", DateTime.utc_now() |> DateTime.to_iso8601())
      |> TreeDx.Capabilities.put_grant()

    assert {:error, %{"code" => "not_found"}} =
             TreeDx.Capabilities.effective_scope(principal, "repo_one")
  end

  test "repository registration validates required fields", %{principal: principal} do
    assert {:error, %{code: "validation_error"}} = TreeDx.Repos.register(%{}, principal)
  end

  test "repository registration rejects paths outside data dir", %{principal: principal} do
    assert {:error, %{code: "validation_error"}} =
             TreeDx.Repos.register(
               %{"name" => "demo", "localPath" => "/tmp/outside.git"},
               principal
             )
  end

  test "repository registration persists placement", %{principal: principal, dir: dir} do
    path = Path.join(dir, "repos/bare/demo")
    create_git_fixture(path)
    {:ok, result} = TreeDx.Repos.register(%{"name" => "demo", "localPath" => path}, principal)
    assert result.repo.repoId =~ "repo_"
    assert result.placement["primaryNodeId"] == "node_local"
  end

  test "repository registration rejects non-git paths", %{principal: principal, dir: dir} do
    path = Path.join(dir, "repos/bare/not-git")
    File.mkdir_p!(path)

    assert {:error, %{code: "validation_error"}} =
             TreeDx.Repos.register(%{"name" => "not-git", "localPath" => path}, principal)
  end

  defp create_git_fixture(path) do
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(path, "README.md"), "hello")
    git(path, ["add", "README.md"])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
