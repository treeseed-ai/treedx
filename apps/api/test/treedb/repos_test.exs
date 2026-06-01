defmodule TreeDb.ReposTest do
  use ExUnit.Case, async: false

  setup do
    dir = Path.join(System.tmp_dir!(), "treedb-repos-test-#{System.unique_integer([:positive])}")
    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")
    {:ok, _} = TreeDb.Store.seed_dev_records("node_local", "http://localhost:4000")
    {:ok, principal: %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}, dir: dir}
  end

  test "effective scope returns dev capabilities", %{principal: principal} do
    {:ok, scope} = TreeDb.Capabilities.effective_scope(principal)
    assert "repos:write" in scope["capabilities"]
  end

  test "repository registration validates required fields", %{principal: principal} do
    assert {:error, %{code: "validation_error"}} = TreeDb.Repos.register(%{}, principal)
  end

  test "repository registration rejects paths outside data dir", %{principal: principal} do
    assert {:error, %{code: "validation_error"}} =
             TreeDb.Repos.register(
               %{"name" => "demo", "localPath" => "/tmp/outside.git"},
               principal
             )
  end

  test "repository registration persists placement", %{principal: principal, dir: dir} do
    path = Path.join(dir, "repos/bare/demo")
    create_git_fixture(path)
    {:ok, result} = TreeDb.Repos.register(%{"name" => "demo", "localPath" => path}, principal)
    assert result.repo.repoId =~ "repo_"
    assert result.placement["primaryNodeId"] == "node_local"
  end

  test "repository registration rejects non-git paths", %{principal: principal, dir: dir} do
    path = Path.join(dir, "repos/bare/not-git")
    File.mkdir_p!(path)

    assert {:error, %{code: "validation_error"}} =
             TreeDb.Repos.register(%{"name" => "not-git", "localPath" => path}, principal)
  end

  defp create_git_fixture(path) do
    File.mkdir_p!(path)
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDB Test"])
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
