defmodule TreeDx.Uploads do
  @moduledoc false

  alias TreeDx.Files.PathPolicy

  def create(workspace_id, params, principal) do
    with {:ok, workspace} <- workspace_context(workspace_id, principal),
         {:ok, path} <- PathPolicy.normalize(params["path"]),
         :ok <- PathPolicy.authorize(workspace, path, truthy?(params["allowProtected"])) do
      upload_id = "upload_#{System.unique_integer([:positive])}"

      session = %{
        uploadId: upload_id,
        workspaceId: workspace_id,
        actorId: actor_id(principal),
        path: path,
        contentType: params["contentType"],
        expectedContentHash: params["expectedContentHash"],
        expectedSha: params["expectedSha"],
        createdAt: now(),
        expiresAt:
          DateTime.utc_now() |> DateTime.add(ttl_seconds(), :second) |> DateTime.to_iso8601(),
        status: "open"
      }

      write_session!(session)
      {:ok, %{upload: public_session(session)}}
    end
  end

  def put_part(workspace_id, upload_id, part_number, bytes, principal) do
    with {:ok, _workspace} <- workspace_context(workspace_id, principal),
         {:ok, session} <- get_session(workspace_id, upload_id, principal),
         :ok <- open_session(session),
         {:ok, number} <- parse_part_number(part_number),
         :ok <- enforce_part_size(bytes) do
      content_hash = hash_bytes(bytes)

      part = %{
        uploadId: upload_id,
        workspaceId: workspace_id,
        partNumber: number,
        contentBase64: Base.encode64(bytes),
        byteLength: byte_size(bytes),
        contentHash: content_hash,
        createdAt: now()
      }

      write_part!(part)
      {:ok, %{part: Map.drop(part, [:contentBase64])}}
    end
  end

  def complete(workspace_id, upload_id, params, principal) do
    with {:ok, _workspace} <- workspace_context(workspace_id, principal),
         {:ok, session} <- get_session(workspace_id, upload_id, principal),
         :ok <- open_session(session),
         parts <- list_parts(workspace_id, upload_id),
         :ok <- contiguous_parts(parts),
         {:ok, bytes} <- join_parts(parts),
         :ok <- enforce_total_size(bytes),
         content_hash <- hash_bytes(bytes),
         :ok <-
           expected_hash(
             content_hash,
             params["expectedContentHash"] || session["expectedContentHash"]
           ),
         {:ok, result} <-
           TreeDx.Blobs.upload_workspace(
             workspace_id,
             %{
               "path" => session["path"],
               "contentType" => params["contentType"] || session["contentType"],
               "expectedSha" => params["expectedSha"] || session["expectedSha"],
               "expectedContentHash" =>
                 params["expectedContentHash"] || session["expectedContentHash"],
               "allowProtected" => params["allowProtected"]
             },
             bytes,
             principal
           ) do
      write_session!(Map.merge(session, %{"status" => "completed", "completedAt" => now()}))
      {:ok, Map.put(result, :upload, %{uploadId: upload_id, status: "completed"})}
    end
  end

  def abort(workspace_id, upload_id, principal) do
    with {:ok, _workspace} <- workspace_context(workspace_id, principal),
         {:ok, session} <- get_session(workspace_id, upload_id, principal) do
      write_session!(Map.merge(session, %{"status" => "aborted", "completedAt" => now()}))
      File.rm_rf(upload_dir(workspace_id, upload_id))
      {:ok, %{upload: %{uploadId: upload_id, workspaceId: workspace_id, status: "aborted"}}}
    end
  end

  defp workspace_context(workspace_id, principal) do
    with {:ok, workspace} when is_map(workspace) <- TreeDx.Store.get_workspace(workspace_id),
         true <- workspace["actorId"] == actor_id(principal),
         {:ok, workspace, _scope} <-
           TreeDx.Workspaces.ensure_policy_current(workspace, principal, "files:write") do
      {:ok, workspace}
    else
      {:ok, nil} -> {:error, %{code: "not_found", message: "Workspace not found."}}
      false -> {:error, %{code: "permission_denied", message: "Permission denied."}}
      other -> other
    end
  end

  defp get_session(workspace_id, upload_id, principal) do
    case Enum.find(
           read_sessions(),
           &(&1["workspaceId"] == workspace_id and &1["uploadId"] == upload_id)
         ) do
      nil ->
        {:error, %{code: "not_found", message: "Upload session not found."}}

      session ->
        if session["actorId"] == actor_id(principal) do
          {:ok, session}
        else
          {:error, %{code: "permission_denied", message: "Permission denied."}}
        end
    end
  end

  defp open_session(%{"status" => "open", "expiresAt" => expires_at}) do
    case DateTime.from_iso8601(expires_at) do
      {:ok, expires, _} ->
        if DateTime.compare(expires, DateTime.utc_now()) == :gt do
          :ok
        else
          {:error, %{code: "conflict", message: "Upload session has expired."}}
        end

      _ ->
        {:error, %{code: "conflict", message: "Upload session is invalid."}}
    end
  end

  defp open_session(_), do: {:error, %{code: "conflict", message: "Upload session is not open."}}

  defp parse_part_number(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, %{code: "validation_error", message: "part number is invalid."}}
    end
  end

  defp parse_part_number(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_part_number(_),
    do: {:error, %{code: "validation_error", message: "part number is invalid."}}

  defp contiguous_parts([]),
    do: {:error, %{code: "validation_error", message: "Upload has no parts."}}

  defp contiguous_parts(parts) do
    expected = Enum.to_list(1..length(parts))
    actual = Enum.map(parts, & &1["partNumber"])

    if actual == expected do
      :ok
    else
      {:error, %{code: "validation_error", message: "Upload parts must be contiguous."}}
    end
  end

  defp join_parts(parts) do
    parts
    |> Enum.map(&Base.decode64(&1["contentBase64"] || ""))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, bytes}, {:ok, acc} ->
        {:cont, {:ok, [bytes | acc]}}

      :error, _ ->
        {:halt, {:error, %{code: "validation_error", message: "Upload part is invalid."}}}
    end)
    |> case do
      {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
      error -> error
    end
  end

  defp enforce_part_size(bytes) do
    if byte_size(bytes) <= part_bytes() do
      :ok
    else
      {:error, %{code: "payload_too_large", message: "Upload part is too large."}}
    end
  end

  defp enforce_total_size(bytes) do
    if byte_size(bytes) <= max_total_bytes() do
      :ok
    else
      {:error, %{code: "payload_too_large", message: "Upload is too large."}}
    end
  end

  defp expected_hash(_actual, nil), do: :ok
  defp expected_hash(actual, actual), do: :ok

  defp expected_hash(_actual, _expected),
    do: {:error, %{code: "conflict", message: "expectedContentHash does not match."}}

  defp public_session(session), do: Map.drop(session, [:actorId])

  defp write_session!(session),
    do: append_jsonl!("workspaces/uploads.tdb", "blob_upload", session)

  defp write_part!(part),
    do:
      append_jsonl!(
        Path.join(["tmp", "uploads", part.workspaceId, part.uploadId, "parts.tdb"]),
        "blob_upload_part",
        part
      )

  defp read_sessions, do: read_jsonl("workspaces/uploads.tdb")

  defp list_parts(workspace_id, upload_id),
    do:
      read_jsonl(Path.join(["tmp", "uploads", workspace_id, upload_id, "parts.tdb"]))
      |> Enum.sort_by(& &1["partNumber"])

  defp upload_dir(workspace_id, upload_id),
    do: Path.join([TreeDx.Store.data_dir(), "tmp", "uploads", workspace_id, upload_id])

  defp append_jsonl!(relative_path, kind, data) do
    path = Path.join(TreeDx.Store.data_dir(), relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{kind: kind, data: data}) <> "\n", [:append])
  end

  defp read_jsonl(relative_path) do
    path = Path.join(TreeDx.Store.data_dir(), relative_path)

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"data" => data}} -> [data]
          _ -> []
        end
      end)
    else
      []
    end
  end

  defp hash_bytes(bytes) do
    case TreeDx.Store.hash_bytes_base64(Base.encode64(bytes)) do
      {:ok, hash} -> hash
      _ -> "blake3:" <> (:crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower))
    end
  end

  defp part_bytes, do: env_int("TREEDX_MULTIPART_PART_BYTES", 8_388_608)
  defp max_total_bytes, do: env_int("TREEDX_MAX_MULTIPART_BLOB_BYTES", 536_870_912)
  defp ttl_seconds, do: env_int("TREEDX_UPLOAD_SESSION_TTL_SECONDS", 86_400)

  defp env_int(name, default),
    do: System.get_env(name, "#{default}") |> Integer.parse() |> elem_or_default(default)

  defp elem_or_default({value, _}, _default), do: value
  defp elem_or_default(_, default), do: default
  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp actor_id(principal),
    do: principal["actorId"] || principal[:actorId] || principal[:actor_id]

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
