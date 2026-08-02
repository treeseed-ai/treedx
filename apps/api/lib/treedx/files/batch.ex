defmodule TreeDx.Files.Batch do
  @moduledoc false

  alias TreeDx.Files.{PathPolicy, WorkspaceFiles}

  @max_files 500
  @max_file_bytes 1_048_576

  def write(workspace_id, %{"files" => files}, principal)
      when is_list(files) and files != [] and length(files) <= @max_files do
    with {:ok, ctx} <- TreeDx.Files.writable_context(workspace_id, principal, "files:write"),
         {:ok, inputs} <- prepare(files, ctx),
         {:ok, records} <- TreeDx.Store.put_workspace_files(inputs) do
      TreeDx.Audit.append("file.batch_written", %{
        actor_id: actor_id(principal),
        tenant_id: tenant_id(principal),
        repo_id: ctx.repo["id"],
        data: %{workspaceId: workspace_id, paths: Enum.map(records, & &1["path"])}
      })

      {:ok, %{files: Enum.map(records, &public_record/1)}}
    end
  end

  def write(_workspace_id, _params, _principal),
    do: {:error, %{code: "validation_error", message: "files must contain between 1 and 500 entries."}}

  defp prepare(files, ctx) do
    Enum.reduce_while(files, {:ok, []}, fn file, {:ok, acc} ->
      case prepare_file(file, ctx) do
        {:ok, input} -> {:cont, {:ok, [input | acc]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, inputs} -> {:ok, Enum.reverse(inputs)}
      error -> error
    end)
  end

  defp prepare_file(%{"path" => requested_path, "content" => content} = file, ctx)
       when is_binary(content) and byte_size(content) <= @max_file_bytes do
    with {:ok, path} <- PathPolicy.normalize(requested_path),
         :ok <- PathPolicy.authorize(ctx.workspace, path, file["allowProtected"] == true),
         {:ok, state} <- WorkspaceFiles.state(ctx, path),
         :ok <- expected_sha(state.sha, file["expectedSha"]) do
      {:ok,
       %{
         workspaceId: ctx.workspace["id"],
         path: path,
         op: "put",
         encoding: "utf8",
         contentBase64: Base.encode64(content),
         expectedSha: file["expectedSha"],
         baseSha: state.base_sha
       }}
    end
  end

  defp prepare_file(_file, _ctx),
    do: {:error, %{code: "validation_error", message: "Each file requires a valid path and UTF-8 content up to 1 MiB."}}

  defp expected_sha(_actual, nil), do: :ok
  defp expected_sha(actual, actual), do: :ok
  defp expected_sha(_actual, _expected), do: {:error, %{code: "conflict", message: "expectedSha does not match."}}

  defp public_record(record),
    do: %{path: record["path"], sha: record["contentHash"], size: record["size"], source: "overlay"}

  defp actor_id(principal), do: principal["actorId"] || principal[:actorId] || principal[:actor_id]
  defp tenant_id(principal), do: principal["tenantId"] || principal[:tenantId] || principal[:tenant_id]
end
