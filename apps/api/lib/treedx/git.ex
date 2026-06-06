defmodule TreeDx.Git do
  @moduledoc false

  def inspect_repository(path) do
    call(&TreeDx.Native.inspect_repository/1, [path])
  end

  def list_refs(path), do: call(&TreeDx.Native.list_refs/1, [path])
  def list_remotes(path), do: call(&TreeDx.Native.list_remotes/1, [path])
  def resolve_ref(path, ref_name), do: call(&TreeDx.Native.resolve_ref/2, [path, ref_name])

  def list_tree(path, ref_name, tree_path \\ nil),
    do: call(&TreeDx.Native.list_tree/3, [path, ref_name, tree_path])

  def list_tree_recursive(path, ref_name, tree_path \\ nil),
    do: call(&TreeDx.Native.list_tree_recursive/3, [path, ref_name, tree_path])

  def read_blob(path, ref_name, blob_path),
    do: call(&TreeDx.Native.read_blob/3, [path, ref_name, blob_path])

  def changed_paths(path, base_ref, head_ref),
    do: call(&TreeDx.Native.changed_paths/3, [path, base_ref, head_ref])

  def fetch_remote(input), do: call(&TreeDx.Native.fetch_remote/1, [Jason.encode!(input)])
  def push_remote(input), do: call(&TreeDx.Native.push_remote/1, [Jason.encode!(input)])

  def commit_overlay(input) do
    input_json = Jason.encode!(input)

    input_path =
      Path.join(System.tmp_dir!(), "treedx-git-worker-#{System.unique_integer([:positive])}.json")

    File.write!(input_path, input_json)

    try do
      case commit_worker(input_path) do
        {:binary, path, args, opts} ->
          run_worker(path, args, opts)

        {:error, error} ->
          {:error, error}
      end
    after
      File.rm(input_path)
    end
  end

  defp call(fun, args) do
    case apply(:erlang, :apply, [fun, args]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      {:error, json} -> {:error, Jason.decode!(json)}
    end
  end

  defp run_worker(path, args, opts) do
    case System.cmd(path, args, Keyword.merge([stderr_to_stdout: true], opts)) do
      {output, 0} ->
        {:ok, Jason.decode!(output)}

      {output, _status} ->
        case Jason.decode(output) do
          {:ok, error} -> {:error, error}
          {:error, _} -> {:error, %{"code" => "git_error", "message" => output, "details" => %{}}}
        end
    end
  end

  defp commit_worker(input_path) do
    release_worker = Path.expand("bin/treedx_git_worker", File.cwd!())

    cond do
      executable = System.find_executable("treedx_git_worker") ->
        {:binary, executable, ["commit-overlay", input_path], []}

      File.exists?(release_worker) ->
        {:binary, release_worker, ["commit-overlay", input_path], []}

      File.exists?(Path.expand("../../target/debug/treedx_git_worker", File.cwd!())) ->
        {:binary, Path.expand("../../target/debug/treedx_git_worker", File.cwd!()),
         ["commit-overlay", input_path], []}

      File.exists?(Path.expand("../../target/release/treedx_git_worker", File.cwd!())) ->
        {:binary, Path.expand("../../target/release/treedx_git_worker", File.cwd!()),
         ["commit-overlay", input_path], []}

      System.find_executable("cargo") ->
        {:binary, "cargo",
         [
           "run",
           "--quiet",
           "-p",
           "treedx_git",
           "--bin",
           "treedx_git_worker",
           "--",
           "commit-overlay",
           input_path
         ], [cd: repo_root()]}

      true ->
        {:error,
         %{
           "code" => "not_implemented",
           "message" => "treedx_git_worker is not available.",
           "details" => %{}
         }}
    end
  end

  defp repo_root do
    System.get_env("TREEDX_ROOT_DIR") || Path.expand("../..", File.cwd!())
  end
end
