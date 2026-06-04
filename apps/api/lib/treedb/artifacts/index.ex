defmodule TreeDb.Artifacts.Index do
  @moduledoc false
  use GenServer

  @table __MODULE__

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_opts) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    refresh_table()
    {:ok, %{}}
  end

  def refresh!, do: GenServer.call(__MODULE__, :refresh, 30_000)

  def list(repo_id) do
    ensure_loaded()

    @table
    |> :ets.lookup({:repo, repo_id})
    |> case do
      [{{:repo, ^repo_id}, ids}] -> ids
      [] -> []
    end
    |> Enum.map(&lookup_artifact/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&deleted?/1)
  end

  def get(repo_id, id) do
    ensure_loaded()

    artifact =
      lookup_artifact(id) ||
        case :ets.lookup(@table, {:snapshot, id}) do
          [{{:snapshot, ^id}, artifact_id}] -> lookup_artifact(artifact_id)
          [] -> nil
        end

    cond do
      is_nil(artifact) ->
        refresh!()
        get_after_refresh(repo_id, id)

      artifact["repoId"] == repo_id and !deleted?(artifact) ->
        artifact

      true ->
        nil
    end
  end

  def mark_deleted(artifact_id, _snapshot_id \\ nil) do
    ensure_loaded()
    :ets.insert(@table, {{:deleted, artifact_id}, true})
    :ok
  end

  def upsert_from_manifest(manifest) when is_map(manifest) do
    artifact = manifest["artifact"] || manifest[:artifact]

    if is_map(artifact) do
      artifact =
        artifact
        |> Map.put_new("repoId", manifest["repoId"])
        |> Map.put_new("snapshotId", manifest["snapshotId"])

      upsert_artifact(artifact)
    end

    :ok
  end

  def handle_call(:refresh, _from, state) do
    refresh_table()
    {:reply, :ok, state}
  end

  defp get_after_refresh(repo_id, id) do
    artifact =
      lookup_artifact(id) ||
        case :ets.lookup(@table, {:snapshot, id}) do
          [{{:snapshot, ^id}, artifact_id}] -> lookup_artifact(artifact_id)
          [] -> nil
        end

    if is_map(artifact) and artifact["repoId"] == repo_id and !deleted?(artifact),
      do: artifact,
      else: nil
  end

  defp refresh_table do
    :ets.delete_all_objects(@table)

    read_jsonl("snapshots/artifacts.tdb")
    |> Enum.each(&upsert_artifact/1)

    read_jsonl("snapshots/artifact_lifecycle.tdb")
    |> Enum.filter(&(&1["status"] == "deleted"))
    |> Enum.each(fn record -> mark_deleted(record["artifactId"], record["snapshotId"]) end)
  end

  defp upsert_artifact(artifact) do
    artifact_id = artifact["artifactId"] || artifact["artifact_id"]
    snapshot_id = artifact["snapshotId"]
    repo_id = artifact["repoId"]

    if is_binary(artifact_id) do
      :ets.insert(@table, {{:artifact, artifact_id}, artifact})
      if is_binary(snapshot_id), do: :ets.insert(@table, {{:snapshot, snapshot_id}, artifact_id})

      if is_binary(repo_id) do
        ids =
          case :ets.lookup(@table, {:repo, repo_id}) do
            [{{:repo, ^repo_id}, existing}] -> Enum.uniq([artifact_id | existing])
            [] -> [artifact_id]
          end

        :ets.insert(@table, {{:repo, repo_id}, ids})
      end
    end
  end

  defp lookup_artifact(id) do
    case :ets.lookup(@table, {:artifact, id}) do
      [{{:artifact, ^id}, artifact}] -> artifact
      [] -> nil
    end
  end

  defp deleted?(artifact) do
    artifact_id = artifact["artifactId"] || artifact["artifact_id"]
    :ets.lookup(@table, {:deleted, artifact_id}) != []
  end

  defp ensure_loaded do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
      refresh_table()
    end
  end

  defp read_jsonl(relative_path) do
    path = Path.join(TreeDb.Store.data_dir(), relative_path)

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Enum.flat_map(fn line ->
        case Jason.decode(String.trim(line)) do
          {:ok, %{"payload" => data}} -> [data]
          {:ok, %{"data" => data}} -> [data]
          _ -> []
        end
      end)
    else
      []
    end
  end
end
