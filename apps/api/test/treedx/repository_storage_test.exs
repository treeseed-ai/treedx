defmodule TreeDx.RepositoryStorageTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "treedx-repository-storage-test-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(dir)
    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")
    {:ok, dir: dir}
  end

  test "validates canonical repository names" do
    assert {:ok, "repo-docs.1"} = TreeDx.RepositoryStorage.validate_name("Repo-Docs.1")

    for invalid <- ["", ".git", "admin", "../repo", "repo/name", "repo name", ".hidden"] do
      assert {:error, %{code: "validation_error"}} =
               TreeDx.RepositoryStorage.validate_name(invalid)
    end
  end

  test "derives managed storage from repository name and data dir", %{dir: dir} do
    assert TreeDx.RepositoryStorage.managed_path("repo-docs") ==
             Path.join([dir, "repositories", "repo-docs"])
  end

  test "validates repository-relative paths only" do
    assert :ok = TreeDx.RepositoryStorage.validate_relative_path("docs/intro.md")

    assert {:error, %{code: "validation_error"}} =
             TreeDx.RepositoryStorage.validate_relative_path("/tmp/repo/docs/intro.md")

    assert {:error, %{code: "validation_error"}} =
             TreeDx.RepositoryStorage.validate_relative_path("../secret")

    assert {:error, %{code: "permission_denied"}} =
             TreeDx.RepositoryStorage.validate_relative_path(".git/config")
  end

  test "managed registration initializes a git repository", %{dir: dir} do
    principal = %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")

    assert {:ok, result} =
             TreeDx.Repos.register(
               %{"repositoryName" => "managed-repo", "createIfMissing" => true},
               principal
             )

    assert result.repo.repositoryName == "managed-repo"
    assert result.repo.storageKind == "managed"
    assert File.exists?(Path.join([dir, "repositories", "managed-repo", ".git"]))
  end

  test "admin local import uses data-dir-relative source paths", %{dir: dir} do
    principal = %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")
    source = Path.join([dir, "imports", "source-repo"])
    File.rm_rf!(source)
    File.mkdir_p!(source)
    git(source, ["init", "-b", "main"])
    git(source, ["config", "user.name", "TreeDX Test"])
    git(source, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(source, "README.md"), "imported\n")
    git(source, ["add", "README.md"])
    git(source, ["commit", "-m", "initial"])

    assert {:ok, result} =
             TreeDx.Repos.import_local(
               %{
                 "repositoryName" => "imported-repo",
                 "sourceRelativePath" => "imports/source-repo"
               },
               principal
             )

    assert result.repo.repositoryName == "imported-repo"
    assert File.exists?(Path.join([dir, "repositories", "imported-repo", ".git"]))
    refute inspect(result) =~ source
  end

  test "admin local import rejects absolute source paths" do
    principal = %{"actorId" => "actor_demo", "tenantId" => "tenant_demo"}
    {:ok, _} = TreeDx.Store.seed_dev_records("node_local", "http://localhost:4000")

    assert {:error, %{code: "validation_error"}} =
             TreeDx.Repos.import_local(
               %{"repositoryName" => "bad-import", "sourceRelativePath" => "/tmp/repo"},
               principal
             )
  end

  defp git(path, args) do
    {_, 0} = System.cmd("git", args, cd: path, stderr_to_stdout: true)
  end
end
