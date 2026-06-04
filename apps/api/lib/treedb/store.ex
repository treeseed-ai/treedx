defmodule TreeDb.Store do
  @moduledoc false

  def data_dir do
    Application.get_env(:treedb, :data_dir) || System.get_env("TREEDB_DATA_DIR") ||
      "/var/lib/treedb"
  end

  def init!(opts \\ %{}) do
    opts = Map.new(opts)
    node_id = Map.get(opts, :node_id) || System.get_env("TREEDB_NODE_ID") || "node_local"
    ensure_lock_marker!()

    {:ok, report} =
      call_json(&TreeDb.Native.init_data_dir/2, data_dir(), Jason.encode!(%{nodeId: node_id}))

    report
  end

  defp ensure_lock_marker! do
    if System.get_env("TREEDB_STORAGE_MODE") != "read_only_recovery" do
      File.mkdir_p!(data_dir())
      lock_path = Path.join(data_dir(), ".treedb.lock")
      current_pid = System.pid()

      case File.write(lock_path, "#{current_pid}\n", [:write, :exclusive]) do
        :ok ->
          :ok

        {:error, :eexist} ->
          existing_pid = lock_path |> File.read!() |> String.trim()

          cond do
            existing_pid == current_pid ->
              :ok

            live_pid?(existing_pid) ->
              raise "TreeDB data directory is already locked by process #{existing_pid}."

            true ->
              File.write!(lock_path, "#{current_pid}\n")
          end

        {:error, reason} ->
          raise "Unable to create TreeDB data directory lock: #{inspect(reason)}"
      end
    end
  end

  defp live_pid?(""), do: false

  defp live_pid?(pid) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  def seed_dev_records(node_id, base_url),
    do: call_json(&TreeDb.Native.seed_dev_records/3, data_dir(), node_id, base_url)

  def seed_local_records(node_id, base_url),
    do: call_json(&TreeDb.Native.seed_local_records/3, data_dir(), node_id, base_url)

  def put_repository(input),
    do: call_json(&TreeDb.Native.put_repository/2, data_dir(), Jason.encode!(input))

  def list_repositories, do: call_json(&TreeDb.Native.list_repositories/1, data_dir())
  def get_repository(repo_id), do: call_json(&TreeDb.Native.get_repository/2, data_dir(), repo_id)

  def get_repository_placement(repo_id),
    do: call_json(&TreeDb.Native.get_repository_placement/2, data_dir(), repo_id)

  def put_repository_placement(input),
    do: call_json(&TreeDb.Native.put_repository_placement/2, data_dir(), Jason.encode!(input))

  def list_nodes, do: call_json(&TreeDb.Native.list_nodes/1, data_dir())
  def get_node(node_id), do: call_json(&TreeDb.Native.get_node/2, data_dir(), node_id)
  def list_mirrors(repo_id), do: call_json(&TreeDb.Native.list_mirrors/2, data_dir(), repo_id)

  def put_mirror(input),
    do: call_json(&TreeDb.Native.put_mirror/2, data_dir(), Jason.encode!(input))

  def build_snapshot_artifact(input),
    do: call_json(&TreeDb.Native.build_snapshot_artifact/2, data_dir(), Jason.encode!(input))

  def get_snapshot_manifest(snapshot_id),
    do: call_json(&TreeDb.Native.get_snapshot_manifest/2, data_dir(), snapshot_id)

  def get_artifact(snapshot_id),
    do: call_json(&TreeDb.Native.get_artifact/2, data_dir(), snapshot_id)

  def read_artifact_bytes(snapshot_id),
    do: call_json(&TreeDb.Native.read_artifact_bytes/2, data_dir(), snapshot_id)

  def compact_storage(input),
    do: call_json(&TreeDb.Native.compact_storage/2, data_dir(), Jason.encode!(input))

  def create_backup(input),
    do: call_json(&TreeDb.Native.create_backup/2, data_dir(), Jason.encode!(input))

  def list_tdb_logs, do: call_json(&TreeDb.Native.list_tdb_logs/1, data_dir())

  def put_graph_refresh_job(input),
    do: call_json(&TreeDb.Native.put_graph_refresh_job/2, data_dir(), Jason.encode!(input))

  def get_graph_refresh_job(repo_id, job_id),
    do: call_json(&TreeDb.Native.get_graph_refresh_job/3, data_dir(), repo_id, job_id)

  def put_search_index_manifest(input),
    do: call_json(&TreeDb.Native.put_search_index_manifest/2, data_dir(), Jason.encode!(input))

  def get_search_index_manifest(repo_id, ref_name),
    do: call_json(&TreeDb.Native.get_search_index_manifest/3, data_dir(), repo_id, ref_name)

  def put_search_index_segment(input),
    do: call_json(&TreeDb.Native.put_search_index_segment/2, data_dir(), Jason.encode!(input))

  def list_search_index_segments(repo_id, ref_name),
    do: call_json(&TreeDb.Native.list_search_index_segments/3, data_dir(), repo_id, ref_name)

  def compact_search_index(input),
    do: call_json(&TreeDb.Native.compact_search_index/2, data_dir(), Jason.encode!(input))

  def put_mirror_sync(input),
    do: call_json(&TreeDb.Native.put_mirror_sync/2, data_dir(), Jason.encode!(input))

  def get_mirror_sync(sync_id),
    do: call_json(&TreeDb.Native.get_mirror_sync/2, data_dir(), sync_id)

  def list_mirror_syncs(input),
    do: call_json(&TreeDb.Native.list_mirror_syncs/2, data_dir(), Jason.encode!(input))

  def put_migration(input),
    do: call_json(&TreeDb.Native.put_migration/2, data_dir(), Jason.encode!(input))

  def get_migration(repo_id, migration_id),
    do: call_json(&TreeDb.Native.get_migration/3, data_dir(), repo_id, migration_id)

  def put_dev_token(input),
    do: call_json(&TreeDb.Native.put_dev_token/2, data_dir(), Jason.encode!(input))

  def get_dev_token_by_hash(hash),
    do: call_json(&TreeDb.Native.get_dev_token_by_hash/2, data_dir(), hash)

  def put_capability_grant(input),
    do: call_json(&TreeDb.Native.put_capability_grant/2, data_dir(), Jason.encode!(input))

  def list_capability_grants(input \\ %{}),
    do: call_json(&TreeDb.Native.list_capability_grants/2, data_dir(), Jason.encode!(input))

  def put_connected_token(input),
    do: call_json(&TreeDb.Native.put_connected_token/2, data_dir(), Jason.encode!(input))

  def get_connected_token(jti),
    do: call_json(&TreeDb.Native.get_connected_token/2, data_dir(), jti)

  def put_policy_refresh(input),
    do: call_json(&TreeDb.Native.put_policy_refresh/2, data_dir(), Jason.encode!(input))

  def list_audit_events(input \\ %{}),
    do: call_json(&TreeDb.Native.list_audit_events/2, data_dir(), Jason.encode!(input))

  def resolve_effective_scope(actor_id, repo_id \\ nil),
    do: call_json(&TreeDb.Native.resolve_effective_scope/3, data_dir(), actor_id, repo_id)

  def append_audit_event(input),
    do: call_json(&TreeDb.Native.append_audit_event/2, data_dir(), Jason.encode!(input))

  def append_audit_events(inputs),
    do: call_json(&TreeDb.Native.append_audit_events/2, data_dir(), Jason.encode!(inputs))

  def put_workspace(input),
    do: call_json(&TreeDb.Native.put_workspace/2, data_dir(), Jason.encode!(input))

  def get_workspace(workspace_id),
    do: call_json(&TreeDb.Native.get_workspace/2, data_dir(), workspace_id)

  def close_workspace(workspace_id),
    do: call_json(&TreeDb.Native.close_workspace/2, data_dir(), workspace_id)

  def cleanup_expired_workspaces,
    do: call_json(&TreeDb.Native.cleanup_expired_workspaces/1, data_dir())

  def quarantine_workspace(input),
    do: call_json(&TreeDb.Native.quarantine_workspace/2, data_dir(), Jason.encode!(input))

  def update_workspace_policy(input),
    do: call_json(&TreeDb.Native.update_workspace_policy/2, data_dir(), Jason.encode!(input))

  def list_quarantined_workspaces(input \\ %{}),
    do: call_json(&TreeDb.Native.list_quarantined_workspaces/2, data_dir(), Jason.encode!(input))

  def put_workspace_file(input),
    do: call_json(&TreeDb.Native.put_workspace_file/2, data_dir(), Jason.encode!(input))

  def get_workspace_file(workspace_id, path),
    do: call_json(&TreeDb.Native.get_workspace_file/3, data_dir(), workspace_id, path)

  def list_workspace_files(workspace_id),
    do: call_json(&TreeDb.Native.list_workspace_files/2, data_dir(), workspace_id)

  def read_workspace_file_content(record),
    do:
      call_json(
        &TreeDb.Native.read_workspace_file_content/2,
        data_dir(),
        Jason.encode!(record)
      )

  def mark_workspace_committed(input),
    do: call_json(&TreeDb.Native.mark_workspace_committed/2, data_dir(), Jason.encode!(input))

  def hash_token(token), do: call_json(&TreeDb.Native.hash_token/1, token)
  def hash_bytes_base64(content), do: call_json(&TreeDb.Native.hash_bytes_base64/1, content)

  def call_json(fun, arg1), do: decode(apply_fun(fun, [arg1]))
  def call_json(fun, arg1, arg2), do: decode(apply_fun(fun, [arg1, arg2]))
  def call_json(fun, arg1, arg2, arg3), do: decode(apply_fun(fun, [arg1, arg2, arg3]))

  defp apply_fun(fun, args), do: apply(:erlang, :apply, [fun, args])

  defp decode({:ok, json}), do: {:ok, Jason.decode!(json)}
  defp decode({:error, json}), do: {:error, Jason.decode!(json)}
end
