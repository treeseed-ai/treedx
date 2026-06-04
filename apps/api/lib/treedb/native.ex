defmodule TreeDb.Native do
  @moduledoc false
  use Rustler, otp_app: :treedb, crate: :treedb_native

  def init_data_dir(_data_dir, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def seed_dev_records(_data_dir, _node_id, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  def seed_local_records(_data_dir, _node_id, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  def put_repository(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_repositories(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_repository(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def get_repository_placement(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_repository_placement(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_nodes(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_node(_data_dir, _node_id), do: :erlang.nif_error(:nif_not_loaded)
  def list_mirrors(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_mirror(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def build_snapshot_artifact(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_snapshot_manifest(_data_dir, _snapshot_id), do: :erlang.nif_error(:nif_not_loaded)
  def get_artifact(_data_dir, _snapshot_id), do: :erlang.nif_error(:nif_not_loaded)
  def read_artifact_bytes(_data_dir, _snapshot_id), do: :erlang.nif_error(:nif_not_loaded)
  def compact_storage(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def create_backup(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_tdb_logs(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def put_graph_refresh_job(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_graph_refresh_job(_data_dir, _repo_id, _job_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_search_index_manifest(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)

  def get_search_index_manifest(_data_dir, _repo_id, _ref_name),
    do: :erlang.nif_error(:nif_not_loaded)

  def put_search_index_segment(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)

  def list_search_index_segments(_data_dir, _repo_id, _ref_name),
    do: :erlang.nif_error(:nif_not_loaded)

  def compact_search_index(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_mirror_sync(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_mirror_sync(_data_dir, _sync_id), do: :erlang.nif_error(:nif_not_loaded)
  def list_mirror_syncs(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_migration(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_migration(_data_dir, _repo_id, _migration_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_dev_token(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_dev_token_by_hash(_data_dir, _token_hash), do: :erlang.nif_error(:nif_not_loaded)
  def put_capability_grant(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_capability_grants(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_connected_token(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_connected_token(_data_dir, _jti), do: :erlang.nif_error(:nif_not_loaded)
  def put_policy_refresh(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_audit_events(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)

  def resolve_effective_scope(_data_dir, _actor_id, _repo_id),
    do: :erlang.nif_error(:nif_not_loaded)

  def append_audit_event(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def append_audit_events(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_workspace(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_workspace(_data_dir, _workspace_id), do: :erlang.nif_error(:nif_not_loaded)
  def close_workspace(_data_dir, _workspace_id), do: :erlang.nif_error(:nif_not_loaded)
  def cleanup_expired_workspaces(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def quarantine_workspace(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def update_workspace_policy(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_quarantined_workspaces(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_workspace_file(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_workspace_file(_data_dir, _workspace_id, _path), do: :erlang.nif_error(:nif_not_loaded)
  def list_workspace_files(_data_dir, _workspace_id), do: :erlang.nif_error(:nif_not_loaded)
  def read_workspace_file_content(_data_dir, _record), do: :erlang.nif_error(:nif_not_loaded)
  def mark_workspace_committed(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def inspect_repository(_path), do: :erlang.nif_error(:nif_not_loaded)
  def list_refs(_path), do: :erlang.nif_error(:nif_not_loaded)
  def list_remotes(_path), do: :erlang.nif_error(:nif_not_loaded)
  def resolve_ref(_path, _ref_name), do: :erlang.nif_error(:nif_not_loaded)
  def list_tree(_path, _ref_name, _tree_path), do: :erlang.nif_error(:nif_not_loaded)
  def list_tree_recursive(_path, _ref_name, _tree_path), do: :erlang.nif_error(:nif_not_loaded)
  def read_blob(_path, _ref_name, _blob_path), do: :erlang.nif_error(:nif_not_loaded)
  def changed_paths(_path, _base_ref, _head_ref), do: :erlang.nif_error(:nif_not_loaded)
  def fetch_remote(_input), do: :erlang.nif_error(:nif_not_loaded)
  def push_remote(_input), do: :erlang.nif_error(:nif_not_loaded)
  def commit_overlay(_input), do: :erlang.nif_error(:nif_not_loaded)
  def build_graph_index(_input), do: :erlang.nif_error(:nif_not_loaded)
  def write_graph_segments(_data_dir, _index), do: :erlang.nif_error(:nif_not_loaded)

  def read_graph_segments(_data_dir, _repo_id, _graph_version),
    do: :erlang.nif_error(:nif_not_loaded)

  def read_latest_graph_manifest(_data_dir, _repo_id, _ref_name),
    do: :erlang.nif_error(:nif_not_loaded)

  def search_graph(_index, _request), do: :erlang.nif_error(:nif_not_loaded)
  def query_graph(_index, _request), do: :erlang.nif_error(:nif_not_loaded)
  def related_nodes(_index, _seed_id, _request), do: :erlang.nif_error(:nif_not_loaded)
  def subgraph(_index, _seed_ids, _request), do: :erlang.nif_error(:nif_not_loaded)
  def build_context_pack(_index, _request), do: :erlang.nif_error(:nif_not_loaded)
  def parse_ctx_dsl(_source), do: :erlang.nif_error(:nif_not_loaded)
  def hash_token(_token), do: :erlang.nif_error(:nif_not_loaded)
  def hash_bytes_base64(_content_base64), do: :erlang.nif_error(:nif_not_loaded)
end
