defmodule TreeDb.Native do
  @moduledoc false
  use Rustler, otp_app: :treedb, crate: :treedb_native

  def init_data_dir(_data_dir, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def seed_dev_records(_data_dir, _node_id, _base_url), do: :erlang.nif_error(:nif_not_loaded)
  def put_repository(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_repositories(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_repository(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def get_repository_placement(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_repository_placement(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def list_nodes(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def get_node(_data_dir, _node_id), do: :erlang.nif_error(:nif_not_loaded)
  def list_mirrors(_data_dir, _repo_id), do: :erlang.nif_error(:nif_not_loaded)
  def put_mirror(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_dev_token(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_dev_token_by_hash(_data_dir, _token_hash), do: :erlang.nif_error(:nif_not_loaded)

  def resolve_effective_scope(_data_dir, _actor_id, _repo_id),
    do: :erlang.nif_error(:nif_not_loaded)

  def append_audit_event(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def put_workspace(_data_dir, _input), do: :erlang.nif_error(:nif_not_loaded)
  def get_workspace(_data_dir, _workspace_id), do: :erlang.nif_error(:nif_not_loaded)
  def close_workspace(_data_dir, _workspace_id), do: :erlang.nif_error(:nif_not_loaded)
  def cleanup_expired_workspaces(_data_dir), do: :erlang.nif_error(:nif_not_loaded)
  def inspect_repository(_path), do: :erlang.nif_error(:nif_not_loaded)
  def list_refs(_path), do: :erlang.nif_error(:nif_not_loaded)
  def list_remotes(_path), do: :erlang.nif_error(:nif_not_loaded)
  def resolve_ref(_path, _ref_name), do: :erlang.nif_error(:nif_not_loaded)
  def list_tree(_path, _ref_name, _tree_path), do: :erlang.nif_error(:nif_not_loaded)
  def read_blob(_path, _ref_name, _blob_path), do: :erlang.nif_error(:nif_not_loaded)
  def hash_token(_token), do: :erlang.nif_error(:nif_not_loaded)
end
