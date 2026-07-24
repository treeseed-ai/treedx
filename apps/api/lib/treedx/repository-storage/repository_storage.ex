defmodule TreeDx.RepositoryStorage do
  @moduledoc false

  @reserved ~w(.git admin system internal tmp workspaces snapshots artifacts keys catalog federation)
  @name_regex ~r/^[a-z0-9][a-z0-9._-]{0,127}$/

  def normalize_name(params) when is_map(params) do
    params["repositoryName"] || params[:repositoryName] || params["name"] ||
      params[:name]
      |> normalize_name()
  end

  def normalize_name(name) when is_binary(name), do: String.downcase(String.trim(name))
  def normalize_name(_), do: ""

  def validate_name(name) do
    normalized = normalize_name(name)

    cond do
      normalized == "" ->
        {:error, %{code: "validation_error", message: "repositoryName is required."}}

      normalized in @reserved ->
        {:error, %{code: "validation_error", message: "repositoryName is reserved."}}

      String.contains?(normalized, ["..", "/", "\\"]) ->
        {:error, %{code: "validation_error", message: "repositoryName is invalid."}}

      not Regex.match?(@name_regex, normalized) ->
        {:error, %{code: "validation_error", message: "repositoryName is invalid."}}

      true ->
        {:ok, normalized}
    end
  end

  def validate_relative_path(path) when is_binary(path) do
    decoded = URI.decode(path)

    cond do
      String.trim(decoded) == "" ->
        {:error, %{code: "validation_error", message: "path is required."}}

      Path.type(decoded) != :relative ->
        {:error, %{code: "validation_error", message: "path must be relative."}}

      String.contains?(decoded, ["..", "\\"]) ->
        {:error, %{code: "validation_error", message: "path is invalid."}}

      decoded == ".git" or String.starts_with?(decoded, ".git/") ->
        {:error, %{code: "permission_denied", message: "Permission denied."}}

      true ->
        :ok
    end
  end

  def validate_relative_path(_),
    do: {:error, %{code: "validation_error", message: "path must be a string."}}

  def storage_relative_path(repository_name), do: Path.join("repositories", repository_name)

  def managed_path(repository_name) do
    Path.join(TreeDx.Store.data_dir(), storage_relative_path(repository_name))
  end

  def mirror_relative_path(repository_name), do: Path.join("mirrors", repository_name)

  def mirror_path(repository_name) do
    Path.join(TreeDx.Store.data_dir(), mirror_relative_path(repository_name))
  end

  def path!(repo) when is_map(repo) do
    cond do
      storage_path = existing_storage_path(repo) ->
        storage_path

      is_binary(repo["localPath"]) and Path.type(repo["localPath"]) == :absolute ->
        repo["localPath"]

      is_binary(repo[:localPath]) and Path.type(repo[:localPath]) == :absolute ->
        repo[:localPath]

      is_binary(repo["localPath"]) and repo["localPath"] != "" ->
        Path.expand(repo["localPath"], TreeDx.Store.data_dir())

      is_binary(repo[:localPath]) and repo[:localPath] != "" ->
        Path.expand(repo[:localPath], TreeDx.Store.data_dir())

      true ->
        repo_name = repo["repositoryName"] || repo[:repositoryName] || repo["name"] || repo[:name]
        managed_path(normalize_name(repo_name))
    end
  end

  defp existing_storage_path(repo) do
    storage_relative_path = repo["storageRelativePath"] || repo[:storageRelativePath]
    local_path = repo["localPath"] || repo[:localPath]

    cond do
      is_binary(storage_relative_path) and storage_relative_path != "" and
          (local_path in [nil, ""] or
             File.exists?(Path.expand(storage_relative_path, TreeDx.Store.data_dir()))) ->
        Path.expand(storage_relative_path, TreeDx.Store.data_dir())

      true ->
        nil
    end
  end

  def ensure_git_repository!(path) do
    if File.exists?(Path.join(path, ".git")) or File.exists?(Path.join(path, "HEAD")) do
      :ok
    else
      File.mkdir_p!(path)

      case System.cmd("git", ["init", "-b", "main"], cd: path, stderr_to_stdout: true) do
        {_output, 0} ->
          File.write!(Path.join(path, ".treedxkeep"), "TreeDX managed repository\n")
          System.cmd("git", ["config", "user.email", "treedx@example.invalid"], cd: path)
          System.cmd("git", ["config", "user.name", "TreeDX"], cd: path)
          System.cmd("git", ["add", ".treedxkeep"], cd: path)
          System.cmd("git", ["commit", "-m", "Initialize TreeDX repository"], cd: path)
          :ok

        {output, _} ->
          raise "Unable to initialize managed repository: #{String.trim(output)}"
      end
    end
  end
end
