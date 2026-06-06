defmodule TreeDx.Artifacts do
  @moduledoc false

  def list(repo_id, _params, principal) do
    with {:ok, _scope} <- TreeDx.Capabilities.require_capability(principal, "files:read", repo_id) do
      artifacts =
        repo_id
        |> TreeDx.Artifacts.Index.list()
        |> Enum.map(&public_artifact/1)

      {:ok, %{artifacts: artifacts}}
    end
  end

  def get(repo_id, artifact_id, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_capability(principal, "files:read", repo_id),
         artifact when is_map(artifact) <- TreeDx.Artifacts.Index.get(repo_id, artifact_id) do
      {:ok, %{artifact: public_artifact(artifact)}}
    else
      nil -> {:error, %{code: "not_found", message: "Artifact not found."}}
      {:error, error} -> {:error, error}
    end
  end

  def delete(repo_id, artifact_id, principal) do
    with {:ok, _scope} <-
           TreeDx.Capabilities.require_capability(principal, "policy:write", repo_id),
         artifact when is_map(artifact) <- TreeDx.Artifacts.Index.get(repo_id, artifact_id) do
      record = %{
        artifactId: artifact_id,
        snapshotId: artifact["snapshotId"],
        status: "deleted",
        deletedAt: now()
      }

      append_jsonl!("snapshots/artifact_lifecycle.tdb", "artifact_lifecycle", record)
      TreeDx.Artifacts.Index.mark_deleted(artifact_id, artifact["snapshotId"])

      TreeDx.Audit.append("artifact.deleted", %{
        actor_id: principal["actorId"],
        tenant_id: principal["tenantId"],
        repo_id: repo_id,
        operation: "artifact.delete",
        status: "ok",
        data: %{artifactId: artifact_id}
      })

      {:ok, %{artifact: Map.merge(public_artifact(artifact), %{status: "deleted"})}}
    else
      nil -> {:error, %{code: "not_found", message: "Artifact not found."}}
      {:error, error} -> {:error, error}
    end
  end

  def cleanup(params, principal) do
    retention_days = params["retentionDays"] || env_int("TREEDX_ARTIFACT_RETENTION_DAYS", 30)
    cutoff = DateTime.utc_now() |> DateTime.add(-retention_days * 86_400, :second)

    expired =
      read_jsonl("snapshots/artifacts.tdb")
      |> Enum.reject(&deleted_by_index?/1)
      |> Enum.filter(fn artifact ->
        case DateTime.from_iso8601(artifact["createdAt"] || "") do
          {:ok, created, _} -> DateTime.compare(created, cutoff) == :lt
          _ -> false
        end
      end)

    Enum.each(expired, fn artifact ->
      append_jsonl!("snapshots/artifact_lifecycle.tdb", "artifact_lifecycle", %{
        artifactId: artifact["artifactId"] || artifact["artifact_id"],
        snapshotId: artifact["snapshotId"],
        status: "deleted",
        deletedAt: now(),
        reason: "retention"
      })

      TreeDx.Artifacts.Index.mark_deleted(
        artifact["artifactId"] || artifact["artifact_id"],
        artifact["snapshotId"]
      )
    end)

    TreeDx.Audit.append("artifact.cleanup", %{
      actor_id: principal["actorId"],
      tenant_id: principal["tenantId"],
      operation: "artifact.cleanup",
      status: "ok",
      data: %{deletedCount: length(expired), retentionDays: retention_days}
    })

    {:ok, %{cleanup: %{deletedCount: length(expired), retentionDays: retention_days}}}
  end

  defp public_artifact(artifact) do
    %{
      artifactId: artifact["artifactId"] || artifact["artifact_id"],
      snapshotId: artifact["snapshotId"],
      format: artifact["format"],
      uri: artifact["uri"],
      checksum: artifact["checksum"],
      byteLength: artifact["size"] || artifact["byteLength"],
      createdAt: artifact["createdAt"],
      status: "available"
    }
  end

  defp deleted_by_index?(artifact) do
    artifact_id = artifact["artifactId"] || artifact["artifact_id"]
    repo_id = artifact["repoId"]

    is_nil(TreeDx.Artifacts.Index.get(repo_id, artifact_id))
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

  defp append_jsonl!(relative_path, kind, data) do
    path = Path.join(TreeDx.Store.data_dir(), relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{kind: kind, data: data}) <> "\n", [:append])
  end

  defp env_int(name, default) do
    case Integer.parse(System.get_env(name, "#{default}")) do
      {value, _} when value > 0 -> value
      _ -> default
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
