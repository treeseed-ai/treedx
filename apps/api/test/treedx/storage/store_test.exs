defmodule TreeDx.StoreTest do
  use ExUnit.Case, async: false

  test "init initializes data dir" do
    dir = Path.join(System.tmp_dir!(), "treedx-store-test-#{System.unique_integer([:positive])}")
    Application.put_env(:treedx, :data_dir, dir)
    report = TreeDx.Store.init!(node_id: "node_local")
    assert File.dir?(Path.join(dir, "repos/bare"))
    assert report["manifestPath"] =~ "manifest.tdb"
  end
end
