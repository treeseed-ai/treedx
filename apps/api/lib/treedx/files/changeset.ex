defmodule TreeDx.Files.Changeset do
  @moduledoc false

  alias TreeDx.Files.{ChangesetPatch, Patch, PathPolicy, WorkspaceFiles}
  alias TreeDx.Runtime.Pool

  @contract "treedx.changeset/v1"
  @max_patch_bytes 8 * 1_048_576
  @max_file_bytes 1_048_576

  def apply(workspace_id, params, principal) do
    Pool.run(:workspace_mutation, fn -> do_apply(workspace_id, params, principal) end)
  end

  defp do_apply(workspace_id, params, principal) do
    with :ok <- require_contract(params),
         {:ok, patch} <- decode_patch(params),
         :ok <- require_patch_digest(patch, params["patchSha256"]),
         {:ok, replay} <- replay(workspace_id, params, patch),
         {:ok, result} <- maybe_apply(replay, workspace_id, params, patch, principal) do
      {:ok, result}
    end
  end

  defp maybe_apply(result, _workspace_id, _params, _patch, _principal) when is_map(result),
    do: {:ok, Map.put(result, "idempotentReplay", true)}

  defp maybe_apply(nil, workspace_id, params, patch, principal) do
    with {:ok, ctx} <- TreeDx.Files.writable_context(workspace_id, principal, "files:write"),
         :ok <- require_base(ctx.workspace, params),
         {:ok, overlays} <- TreeDx.Store.list_workspace_files(workspace_id),
         :ok <- require_workspace_version(ctx, overlays, params),
         {:ok, changes} <- ChangesetPatch.parse(patch),
         {:ok, inputs, receipt_files} <- prepare(changes, ctx),
         {:ok, records} <- TreeDx.Store.put_workspace_files(inputs) do
      result = receipt(ctx, params, patch, records, receipt_files, overlays)

      with {:ok, _record} <- persist_replay(workspace_id, params, patch, result) do
        audit(ctx, result)
        {:ok, result}
      end
    end
  end

  defp require_contract(%{"contract" => @contract}), do: :ok
  defp require_contract(_), do: validation("contract must be #{@contract}.")

  defp decode_patch(%{"patch" => patch}) when is_binary(patch), do: bounded_patch(patch)
  defp decode_patch(_), do: validation("patch is required.")

  defp bounded_patch(patch) when is_binary(patch) do
    cond do
      byte_size(patch) > @max_patch_bytes -> too_large("expanded patch exceeds 8 MiB.")
      not String.valid?(patch) -> validation("patch must be valid UTF-8 text.")
      true -> {:ok, patch}
    end
  end

  defp bounded_patch(_), do: validation("patch must be valid UTF-8 text.")

  defp require_patch_digest(patch, expected) when is_binary(expected) do
    actual = sha256(patch)

    if secure_equal(actual, String.downcase(expected)),
      do: :ok,
      else: conflict("patch digest differs.")
  end

  defp require_patch_digest(_patch, _expected), do: validation("patchSha256 is required.")

  defp replay(workspace_id, params, patch) do
    patch_hash = sha256(patch)

    case params["idempotencyKey"] do
      key when is_binary(key) and byte_size(key) in 8..200 ->
        id = replay_id(workspace_id, key)

        case TreeDx.Store.get_idempotency_record(id) do
          {:ok, nil} ->
            {:ok, nil}

          {:ok, %{"bodyHash" => hash, "responseJson" => response}} ->
            if hash == patch_hash do
              {:ok, response}
            else
              {:error,
               %{
                 code: "idempotency_conflict",
                 message: "idempotency key was already used for another patch."
               }}
            end

          {:ok, _record} ->
            {:error,
             %{
               code: "idempotency_conflict",
               message: "idempotency key was already used for another patch."
             }}

          error ->
            error
        end

      _ ->
        validation("idempotencyKey must contain 8 to 200 bytes.")
    end
  end

  defp require_base(workspace, params) do
    cond do
      params["baseCommitSha"] != workspace["baseCommitSha"] -> conflict("baseCommitSha is stale.")
      params["baseRef"] != workspace["baseRef"] -> conflict("baseRef differs from the workspace.")
      true -> :ok
    end
  end

  defp require_workspace_version(ctx, overlays, params) do
    expected_version = params["expectedWorkspaceVersion"]
    expected_head = params["expectedDestinationRefHead"]

    cond do
      is_binary(expected_version) ->
        if expected_version == workspace_version(ctx.workspace, overlays),
          do: :ok,
          else: conflict("workspace version is stale.")

      is_binary(expected_head) ->
        require_destination_head(ctx, expected_head)

      true ->
        validation("expectedWorkspaceVersion or expectedDestinationRefHead is required.")
    end
  end

  defp require_destination_head(ctx, expected) do
    path = TreeDx.RepositoryStorage.path!(ctx.repo)
    base_commit = ctx.workspace["baseCommitSha"]

    case TreeDx.Git.resolve_ref(path, ctx.workspace["branchName"]) do
      {:ok, %{"target" => ^expected}} -> :ok
      {:error, %{"code" => "not_found"}} when expected == base_commit -> :ok
      {:error, %{code: "not_found"}} when expected == base_commit -> :ok
      {:ok, _} -> conflict("destination ref head is stale.")
      {:error, %{"code" => "not_found"}} -> conflict("destination ref head is stale.")
      {:error, %{code: "not_found"}} -> conflict("destination ref head is stale.")
      other -> other
    end
  end

  defp prepare(changes, ctx) do
    Enum.reduce_while(changes, {:ok, [], []}, fn change, {:ok, inputs, receipts} ->
      case prepare_change(change, ctx) do
        {:ok, input, receipt} -> {:cont, {:ok, [input | inputs], [receipt | receipts]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, inputs, receipts} -> {:ok, Enum.reverse(inputs), Enum.reverse(receipts)}
      error -> error
    end)
  end

  defp prepare_change(change, ctx) do
    with {:ok, path} <- PathPolicy.normalize(change.path),
         :ok <- PathPolicy.authorize(ctx.workspace, path, false),
         {:ok, state} <- WorkspaceFiles.state(ctx, path),
         :ok <- require_operation_state(change.op, state),
         {:ok, content} <- apply_patch(change, state),
         :ok <- validate_result(change.op, content) do
      {:ok, input(change.op, ctx.workspace["id"], path, content, state),
       file_receipt(path, content, state)}
    end
  end

  defp require_operation_state(:create, %{source: :missing}), do: :ok
  defp require_operation_state(:create, _), do: conflict("create target already exists.")

  defp require_operation_state(op, %{source: source})
       when op in [:modify, :delete] and source != :missing,
       do: :ok

  defp require_operation_state(_, _), do: conflict("update or delete target does not exist.")

  defp apply_patch(%{op: :create, patch: patch, path: path}, _state),
    do: Patch.apply("", patch, path)

  defp apply_patch(%{patch: patch, path: path}, state),
    do: Patch.apply(state.content, patch, path)

  defp validate_result(:delete, ""), do: :ok
  defp validate_result(:delete, _), do: validation("delete patch must remove the complete file.")

  defp validate_result(_op, content)
       when byte_size(content) <= @max_file_bytes and is_binary(content),
       do: :ok

  defp validate_result(_op, _content), do: too_large("resulting text file exceeds 1 MiB.")

  defp input(:delete, workspace_id, path, _content, state),
    do: %{
      workspaceId: workspace_id,
      path: path,
      op: "delete",
      expectedSha: state.sha,
      baseSha: state.base_sha
    }

  defp input(_op, workspace_id, path, content, state),
    do: %{
      workspaceId: workspace_id,
      path: path,
      op: "put",
      encoding: "utf8",
      contentBase64: Base.encode64(content),
      expectedSha: state.sha,
      baseSha: state.base_sha
    }

  defp file_receipt(path, content, state),
    do: %{
      path: path,
      beforeSha256: content_sha(state.content),
      afterSha256: content_sha(content),
      byteLength: byte_size(content)
    }

  defp receipt(ctx, params, patch, records, files, previous_overlays) do
    changed_paths = Enum.map(files, & &1.path)
    resulting_overlays = merge_overlays(previous_overlays, records)

    %{
      contract: @contract,
      repositoryId: ctx.repo["id"],
      workspaceId: ctx.workspace["id"],
      baseRef: ctx.workspace["baseRef"],
      baseCommitSha: ctx.workspace["baseCommitSha"],
      resultCommitSha: nil,
      branch: ctx.workspace["branchName"],
      changedPaths: changed_paths,
      files: files,
      patchSha256: sha256(patch),
      idempotencyKey: params["idempotencyKey"],
      idempotentReplay: false,
      workspaceVersion: workspace_version(ctx.workspace, resulting_overlays)
    }
  end

  defp merge_overlays(existing, records),
    do:
      Map.values(
        Map.merge(Map.new(existing, &{&1["path"], &1}), Map.new(records, &{&1["path"], &1}))
      )

  defp workspace_version(workspace, overlays) do
    material =
      overlays
      |> Enum.map(&[&1["path"], &1["op"], &1["contentHash"]])
      |> Enum.sort()
      |> Jason.encode!()

    sha256(workspace["baseCommitSha"] <> "\n" <> material)
  end

  defp persist_replay(workspace_id, params, patch, result) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    TreeDx.Store.put_idempotency_record(%{
      id: replay_id(workspace_id, params["idempotencyKey"]),
      method: "POST",
      path: "/workspaces/#{workspace_id}/changesets",
      bodyHash: sha256(patch),
      status: "200",
      responseJson: result,
      createdAt: now,
      expiresAt: DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()
    })
  end

  defp replay_id(workspace_id, key), do: "changeset:" <> sha256(workspace_id <> ":" <> key)
  defp content_sha(nil), do: nil
  defp content_sha(content), do: sha256(content)
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp secure_equal(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_equal(_, _), do: false

  defp audit(ctx, result) do
    TreeDx.Audit.append("changeset.applied", %{
      actor_id: ctx.principal["actorId"] || ctx.principal[:actor_id],
      tenant_id: ctx.principal["tenantId"] || ctx.principal[:tenant_id],
      repo_id: ctx.repo["id"],
      data: %{
        workspaceId: ctx.workspace["id"],
        changedPaths: result.changedPaths,
        patchSha256: result.patchSha256
      }
    })
  end

  defp validation(message), do: {:error, %{code: "validation_error", message: message}}
  defp conflict(message), do: {:error, %{code: "conflict", message: message}}
  defp too_large(message), do: {:error, %{code: "payload_too_large", message: message}}
end
