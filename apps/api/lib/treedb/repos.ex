defmodule TreeDb.Repos do
  @moduledoc false

  def create(params, principal),
    do: register(Map.put_new(params, "createIfMissing", true), principal)

  def import_local(params, principal) do
    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "repos:write", nil),
         {:ok, repository_name} <- TreeDb.RepositoryStorage.validate_name(params),
         {:ok, source} <- import_source_path(params["sourceRelativePath"]),
         {:ok, destination} <- copy_import_source(repository_name, source),
         {:ok, repo} <-
           put_repository_record(
             %{
               name: repository_name,
               repositoryName: repository_name,
               storageRelativePath:
                 TreeDb.RepositoryStorage.storage_relative_path(repository_name),
               localPath: "",
               defaultRef: params["defaultRef"] || "refs/heads/main",
               remoteUrl: nil
             },
             repository_name
           ),
         {:ok, placement} <- ensure_placement(repo) do
      TreeDb.Audit.append("repo.imported_local", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo["id"],
        data: %{name: repo["name"], source: "data_dir_relative"}
      })

      {:ok,
       %{
         repo: public_repo(repo),
         placement: public_placement(placement),
         imported: %{storageKind: "managed", destination: Path.basename(destination)}
       }}
    end
  end

  def register(params, principal) do
    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "repos:write", nil),
         {:ok, input} <- normalize_registration(params),
         :ok <- ensure_registration_path(input, params),
         {:ok, repo} <- put_repository_record(input, input.repositoryName || input.name),
         {:ok, placement} <- ensure_placement(repo) do
      TreeDb.Audit.append("repo.registered", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo["id"],
        data: %{name: repo["name"]}
      })

      {:ok, %{repo: public_repo(repo), placement: public_placement(placement)}}
    end
  end

  def list(principal) do
    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "repos:read", nil) do
      with {:ok, repos} <- TreeDb.Store.list_repositories() do
        {:ok, Enum.map(repos, &public_repo/1)}
      end
    end
  end

  def get(repo_id, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(principal, "repos:read", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id) do
      {:ok, public_repo(repo)}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def status(repo_id, principal) do
    with {:ok, _scope} <-
           TreeDb.Capabilities.require_capability(principal, "repos:read", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         {:ok, git} <- TreeDb.Git.inspect_repository(TreeDb.RepositoryStorage.path!(repo)),
         {:ok, placement} <- TreeDb.Store.get_repository_placement(repo_id) do
      TreeDb.Audit.append("repo.status_inspected", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id
      })

      {:ok, %{repo: public_repo(repo), git: public_git(git), placement: placement}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def refs(repo_id, principal) do
    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "git:read", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         {:ok, refs} <- TreeDb.Git.list_refs(TreeDb.RepositoryStorage.path!(repo)) do
      TreeDb.Audit.append("repo.refs_listed", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id
      })

      {:ok, %{repo: public_repo(repo), refs: refs}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def remotes(repo_id, principal) do
    with {:ok, _scope} <- TreeDb.Capabilities.require_capability(principal, "git:read", repo_id),
         {:ok, repo} when is_map(repo) <- TreeDb.Store.get_repository(repo_id),
         {:ok, remotes} <- TreeDb.Git.list_remotes(TreeDb.RepositoryStorage.path!(repo)) do
      TreeDb.Audit.append("repo.remotes_listed", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id
      })

      {:ok, %{repo: public_repo(repo), remotes: remotes}}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Repository not found."}}
      other -> other
    end
  end

  def sync(repo_id, params, principal), do: TreeDb.Pushes.fetch(repo_id, params, principal)

  defp normalize_registration(params) do
    with {:ok, repository_name} <- TreeDb.RepositoryStorage.validate_name(params),
         :ok <- validate_no_remote_register(params) do
      storage_relative_path = TreeDb.RepositoryStorage.storage_relative_path(repository_name)

      {:ok,
       %{
         name: repository_name,
         repositoryName: repository_name,
         storageRelativePath: storage_relative_path,
         localPath: legacy_local_path(params),
         defaultRef: params["defaultRef"] || "refs/heads/main",
         remoteUrl: params["remoteUrl"]
       }}
    end
  end

  defp validate_no_remote_register(%{"placement" => %{"mode" => mode}})
       when mode in ["auto", "node"] do
    {:error,
     %{
       code: "validation_error",
       message: "Remote or automatic placement requires POST /api/v1/repos."
     }}
  end

  defp validate_no_remote_register(_), do: :ok

  defp legacy_local_path(params) do
    case params["localPath"] do
      path when is_binary(path) and path != "" -> Path.expand(path)
      _ -> ""
    end
  end

  defp ensure_registration_path(input, params) do
    path = TreeDb.RepositoryStorage.path!(input)

    create? =
      params["createIfMissing"] in [true, "true", "1", 1] or params["localPath"] in [nil, ""]

    cond do
      is_binary(params["localPath"]) and params["localPath"] != "" ->
        validate_legacy_registered_path(params["localPath"])

      File.exists?(path) ->
        validate_registered_path(path)

      create? ->
        TreeDb.RepositoryStorage.ensure_git_repository!(path)

      true ->
        {:error, %{code: "not_found", message: "Managed repository path does not exist."}}
    end
  end

  defp ensure_placement(repo) do
    input = %{
      repositoryId: repo["id"],
      primaryNodeId: System.get_env("TREEDB_NODE_ID") || "node_local",
      mirrorNodeIds: [],
      readPolicy: "primary_or_mirror",
      writePolicy: "primary_only",
      migrationState: "stable"
    }

    case TreeDb.Store.put_repository_placement(input) do
      {:ok, placement} -> {:ok, placement}
      :ok -> TreeDb.Store.get_repository_placement(repo["id"])
      other -> other
    end
  end

  defp put_repository_record(input, repository_name) do
    case TreeDb.Store.put_repository(input) do
      {:ok, repo} ->
        {:ok, repo}

      :ok ->
        with {:ok, repos} <- TreeDb.Store.list_repositories(),
             repo when is_map(repo) <-
               Enum.find(repos, &((&1["repositoryName"] || &1["name"]) == repository_name)) do
          {:ok, repo}
        else
          _ -> {:error, %{code: "internal_error", message: "Repository record was not returned."}}
        end

      other ->
        other
    end
  end

  defp validate_legacy_registered_path(local_path) do
    data_dir = Path.expand(TreeDb.Store.data_dir())

    cond do
      Path.type(local_path) != :absolute ->
        {:error, %{code: "validation_error", message: "localPath must be absolute."}}

      !String.starts_with?(Path.expand(local_path), data_dir) ->
        {:error, %{code: "validation_error", message: "localPath must be under TREEDB_DATA_DIR."}}

      true ->
        validate_registered_path(Path.expand(local_path))
    end
  end

  defp validate_registered_path(path) do
    with {:ok, git} <- TreeDb.Git.inspect_repository(path) do
      cond do
        git["exists"] != true ->
          {:error, %{code: "validation_error", message: "repository storage must exist."}}

        git["isGitRepository"] != true ->
          {:error,
           %{code: "validation_error", message: "repository storage must be a Git repository."}}

        true ->
          :ok
      end
    end
  end

  defp import_source_path(path) when is_binary(path) do
    with :ok <- TreeDb.RepositoryStorage.validate_relative_path(path) do
      relative = path |> URI.decode() |> String.split("/", trim: true) |> Enum.join("/")
      source = Path.expand(relative, TreeDb.Store.data_dir())
      data_dir = Path.expand(TreeDb.Store.data_dir())

      cond do
        !String.starts_with?(source, data_dir <> "/") and source != data_dir ->
          {:error, %{code: "validation_error", message: "sourceRelativePath is invalid."}}

        true ->
          with :ok <- validate_registered_path(source), do: {:ok, source}
      end
    end
  end

  defp import_source_path(_),
    do: {:error, %{code: "validation_error", message: "sourceRelativePath is required."}}

  defp copy_import_source(repository_name, source) do
    destination = TreeDb.RepositoryStorage.managed_path(repository_name)

    cond do
      File.exists?(destination) ->
        {:error, %{code: "conflict", message: "Managed repository already exists."}}

      true ->
        File.mkdir_p!(Path.dirname(destination))

        case hardlink_copy(source, destination) do
          :ok ->
            {:ok, destination}

          {:error, _reason} ->
            File.rm_rf(destination)
            recursive_copy(source, destination)
        end
    end
  end

  defp hardlink_copy(source, destination) do
    cond do
      cp = System.find_executable("cp") ->
        run_copy_command(cp, ["-al", source, destination])

      File.exists?("/bin/busybox") ->
        run_copy_command("/bin/busybox", ["cp", "-a", "-l", source, destination])

      true ->
        {:error, :unavailable}
    end
  end

  defp run_copy_command(command, args) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, String.trim(output)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp recursive_copy(source, destination) do
    case File.cp_r(source, destination) do
      {:ok, _files} ->
        {:ok, destination}

      :ok ->
        {:ok, destination}

      {:error, reason} ->
        File.rm_rf(destination)
        {:error, file_error(reason)}

      {:error, reason, _path} ->
        File.rm_rf(destination)
        {:error, file_error(reason)}

      {:error, _source, _target, reason} ->
        File.rm_rf(destination)
        {:error, file_error(reason)}
    end
  end

  defp file_error(reason) do
    case reason do
      :enospc ->
        %{
          code: "service_unavailable",
          message: "Repository import failed because storage is full.",
          details: %{reason: "insufficient_storage"}
        }

      _ ->
        %{
          code: "internal_error",
          message: "Repository import failed.",
          details: %{reason: inspect(reason)}
        }
    end
  end

  defp public_repo(repo) do
    %{
      repoId: repo["id"],
      repositoryName: repo["repositoryName"] || repo["name"],
      name: repo["repositoryName"] || repo["name"],
      defaultRef: repo["defaultRef"],
      status: repo["status"],
      storageKind: repo["storageKind"] || "managed",
      remoteUrl: repo["remoteUrl"]
    }
  end

  defp public_placement(nil), do: nil
  defp public_placement(placement), do: %{"primaryNodeId" => placement["primaryNodeId"]}

  defp public_git(git) do
    git
    |> Map.drop(["path", "repoPath", "gitDir", "worktreePath"])
  end
end
