defmodule TreeDx.ArtifactIndexTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "treedx-artifact-index-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:treedx, :data_dir, dir)
    TreeDx.Store.init!(node_id: "node_local")

    on_exit(fn ->
      Application.delete_env(:treedx, :data_dir)
      cleanup_dir(dir)
    end)

    :ok
  end

  test "artifact index upserts, lists, gets, and marks deleted" do
    manifest = %{
      "repoId" => "repo_demo",
      "snapshotId" => "snap_demo",
      "artifact" => %{
        "artifactId" => "artifact_demo",
        "snapshotId" => "snap_demo",
        "repoId" => "repo_demo",
        "format" => "tar.zst",
        "uri" => "treedx://artifact/snap_demo",
        "checksum" => "blake3:abc",
        "byteLength" => 12,
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    TreeDx.Artifacts.Index.upsert_from_manifest(manifest)

    assert [%{"artifactId" => "artifact_demo"}] = TreeDx.Artifacts.Index.list("repo_demo")

    assert %{"artifactId" => "artifact_demo"} =
             TreeDx.Artifacts.Index.get("repo_demo", "snap_demo")

    TreeDx.Artifacts.Index.mark_deleted("artifact_demo", "snap_demo")

    assert [] = TreeDx.Artifacts.Index.list("repo_demo")
    assert is_nil(TreeDx.Artifacts.Index.get("repo_demo", "artifact_demo"))
  end

  defp cleanup_dir(dir, attempts \\ 5)

  defp cleanup_dir(dir, attempts) when attempts > 1 do
    case File.rm_rf(dir) do
      {:ok, _} ->
        :ok

      {:error, _reason, _path} ->
        Process.sleep(25)
        cleanup_dir(dir, attempts - 1)
    end
  end

  defp cleanup_dir(dir, _attempts) do
    File.rm_rf(dir)
    :ok
  end
end
