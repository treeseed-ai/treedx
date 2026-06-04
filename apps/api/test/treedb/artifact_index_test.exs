defmodule TreeDb.ArtifactIndexTest do
  use ExUnit.Case, async: false

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "treedb-artifact-index-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:treedb, :data_dir, dir)
    TreeDb.Store.init!(node_id: "node_local")

    on_exit(fn -> File.rm_rf!(dir) end)
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
        "uri" => "treedb://artifact/snap_demo",
        "checksum" => "blake3:abc",
        "byteLength" => 12,
        "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    TreeDb.Artifacts.Index.upsert_from_manifest(manifest)

    assert [%{"artifactId" => "artifact_demo"}] = TreeDb.Artifacts.Index.list("repo_demo")

    assert %{"artifactId" => "artifact_demo"} =
             TreeDb.Artifacts.Index.get("repo_demo", "snap_demo")

    TreeDb.Artifacts.Index.mark_deleted("artifact_demo", "snap_demo")

    assert [] = TreeDb.Artifacts.Index.list("repo_demo")
    assert is_nil(TreeDb.Artifacts.Index.get("repo_demo", "artifact_demo"))
  end
end
