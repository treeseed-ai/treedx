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

  def promote_ref(repo_path, source_ref, destination_ref, expected_destination) do
    with {:ok, %{"target" => source_sha}} <- resolve_ref(repo_path, source_ref),
         {:ok, {destination_sha, destination_cas}} <-
           promotion_destination(repo_path, destination_ref, expected_destination),
         :ok <- require_expected_or_applied(destination_sha, expected_destination, source_sha),
         :ok <- require_fast_forward(repo_path, destination_sha, source_sha),
         :ok <- update_ref_if_needed(repo_path, destination_ref, destination_cas, source_sha) do
      {:ok,
       %{
         "sourceRef" => source_ref,
         "destinationRef" => destination_ref,
         "beforeHead" => destination_sha,
         "afterHead" => source_sha,
         "status" => if(destination_sha == source_sha, do: "already_current", else: "promoted")
       }}
    else
      other ->
        other
    end
  end

  defp promotion_destination(repo_path, destination_ref, expected_destination) do
    case resolve_ref(repo_path, destination_ref) do
      {:ok, %{"target" => destination_sha}} ->
        {:ok, {destination_sha, destination_sha}}

      {:error, %{code: "not_found"}} ->
        missing_promotion_destination(repo_path, expected_destination)

      {:error, %{"code" => "not_found"}} ->
        missing_promotion_destination(repo_path, expected_destination)

      other ->
        other
    end
  end

  defp missing_promotion_destination(repo_path, expected_destination)
       when is_binary(expected_destination) and expected_destination != "" do
    case git(repo_path, ["cat-file", "-e", "#{expected_destination}^{commit}"]) do
      {_output, 0} ->
        {:ok, {expected_destination, ""}}

      _ ->
        {:error,
         %{
           code: "conflict",
           message: "The reviewed base is unavailable for initial ref promotion."
         }}
    end
  end

  defp missing_promotion_destination(_repo_path, _expected_destination),
    do: {:error, %{code: "validation_error", message: "expectedDestinationHead is required."}}

  def retire_ref(repo_path, ref_name, merged_into_ref, expected_head, expected_merged_head) do
    with {:ok, %{"target" => merged_head}} <- resolve_ref(repo_path, merged_into_ref),
         :ok <- require_exact_head(merged_head, expected_merged_head, "merged destination"),
         {:ok, result} <-
           retire_existing_ref(repo_path, ref_name, merged_into_ref, expected_head, merged_head) do
      {:ok, result}
    end
  end

  def discard_ref(repo_path, ref_name, expected_head) do
    case resolve_ref(repo_path, ref_name) do
      {:ok, %{"target" => head}} ->
        with :ok <- require_exact_head(head, expected_head, "discarded ref"),
             :ok <- delete_ref(repo_path, ref_name, head) do
          {:ok, %{"ref" => ref_name, "head" => head, "status" => "discarded"}}
        end

      {:error, %{code: "not_found"}} ->
        {:ok, %{"ref" => ref_name, "head" => expected_head, "status" => "already_discarded"}}

      {:error, %{"code" => "not_found"}} ->
        {:ok, %{"ref" => ref_name, "head" => expected_head, "status" => "already_discarded"}}

      other ->
        other
    end
  end

  defp retire_existing_ref(repo_path, ref_name, merged_into_ref, expected_head, merged_head) do
    case resolve_ref(repo_path, ref_name) do
      {:ok, %{"target" => head}} ->
        with :ok <- require_exact_head(head, expected_head, "retired ref"),
             :ok <- require_fast_forward(repo_path, head, merged_head),
             :ok <- delete_ref(repo_path, ref_name, head) do
          {:ok,
           %{
             "ref" => ref_name,
             "mergedIntoRef" => merged_into_ref,
             "head" => head,
             "mergedIntoHead" => merged_head,
             "status" => "retired"
           }}
        end

      {:error, %{code: "not_found"}} ->
        {:ok,
         %{
           "ref" => ref_name,
           "mergedIntoRef" => merged_into_ref,
           "head" => expected_head,
           "mergedIntoHead" => merged_head,
           "status" => "already_retired"
         }}

      {:error, %{"code" => "not_found"}} ->
        {:ok,
         %{
           "ref" => ref_name,
           "mergedIntoRef" => merged_into_ref,
           "head" => expected_head,
           "mergedIntoHead" => merged_head,
           "status" => "already_retired"
         }}

      other ->
        other
    end
  end

  defp require_exact_head(actual, expected, label) when is_binary(expected) and expected != "" do
    if actual == expected,
      do: :ok,
      else: {:error, %{code: "conflict", message: "The #{label} head changed before retirement."}}
  end

  defp require_exact_head(_actual, _expected, label),
    do: {:error, %{code: "validation_error", message: "The expected #{label} head is required."}}

  defp delete_ref(repo_path, ref_name, expected_head) do
    case git(repo_path, ["update-ref", "-d", ref_name, expected_head]) do
      {_output, 0} -> :ok
      _ -> {:error, %{code: "conflict", message: "The retired ref changed during deletion."}}
    end
  end

  defp update_ref_if_needed(_repo_path, _destination_ref, sha, sha), do: :ok

  defp update_ref_if_needed(repo_path, destination_ref, destination_sha, source_sha) do
    case git(repo_path, ["update-ref", destination_ref, source_sha, destination_sha]) do
      {_output, 0} ->
        :ok

      {_output, _status} ->
        {:error, %{code: "conflict", message: "The destination ref changed during promotion."}}
    end
  end

  defp require_expected_or_applied(destination_sha, _expected, source_sha)
       when destination_sha == source_sha,
       do: :ok

  defp require_expected_or_applied(destination_sha, expected, _source_sha),
    do: require_expected_destination(destination_sha, expected)

  defp require_expected_destination(destination_sha, expected)
       when is_binary(expected) and expected != "" do
    if destination_sha == expected,
      do: :ok,
      else:
        {:error,
         %{code: "conflict", message: "The destination ref no longer matches the reviewed base."}}
  end

  defp require_expected_destination(_destination_sha, _expected),
    do: {:error, %{code: "validation_error", message: "expectedDestinationHead is required."}}

  defp require_fast_forward(repo_path, destination_sha, source_sha) do
    case git(repo_path, ["merge-base", "--is-ancestor", destination_sha, source_sha]) do
      {_output, 0} -> :ok
      _ -> {:error, %{code: "conflict", message: "Ref promotion must be a fast-forward."}}
    end
  end

  defp git(repo_path, args) do
    System.cmd("git", ["-c", "safe.directory=#{repo_path}" | args],
      cd: repo_path,
      stderr_to_stdout: true
    )
  end

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

      executable = target_worker("debug") ->
        {:binary, executable, ["commit-overlay", input_path], []}

      executable = target_worker("release") ->
        {:binary, executable, ["commit-overlay", input_path], []}

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

  defp target_worker(profile) do
    candidates =
      [
        System.get_env("CARGO_TARGET_DIR"),
        Path.expand("../../target", File.cwd!())
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Path.expand("treedx_git_worker", Path.join(&1, profile)))

    Enum.find(candidates, &File.exists?/1)
  end
end
