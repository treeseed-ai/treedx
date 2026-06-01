defmodule TreeDb.Git do
  @moduledoc false

  def inspect_repository(path) do
    call(&TreeDb.Native.inspect_repository/1, [path])
  end

  def list_refs(path), do: call(&TreeDb.Native.list_refs/1, [path])
  def list_remotes(path), do: call(&TreeDb.Native.list_remotes/1, [path])
  def resolve_ref(path, ref_name), do: call(&TreeDb.Native.resolve_ref/2, [path, ref_name])

  def list_tree(path, ref_name, tree_path \\ nil),
    do: call(&TreeDb.Native.list_tree/3, [path, ref_name, tree_path])

  def read_blob(path, ref_name, blob_path),
    do: call(&TreeDb.Native.read_blob/3, [path, ref_name, blob_path])

  defp call(fun, args) do
    case apply(:erlang, :apply, [fun, args]) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      {:error, json} -> {:error, Jason.decode!(json)}
    end
  end
end
