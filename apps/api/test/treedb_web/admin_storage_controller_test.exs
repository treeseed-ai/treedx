defmodule TreeDbWeb.AdminStorageControllerTest do
  use TreeDbWeb.ConnCase, async: false

  test "admin storage endpoints are protected and redact paths", %{conn: conn} do
    token = dev_token!(conn)

    unauthorized = get(build_conn(), "/api/v1/admin/storage/health")
    assert json_response(unauthorized, 401)["error"]["code"] == "authentication_required"

    health =
      build_conn()
      |> auth_conn(token)
      |> get("/api/v1/admin/storage/health")
      |> json!(200)

    assert health["storage"]["dataDir"] == "redacted"
    assert health["storage"]["nativeLoaded"] == true
    assert_public_hygiene!(health)

    check =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/check", %{})
      |> json!(200)

    assert check["check"]["status"] == "ok"
    assert_public_hygiene!(check)

    recover =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/recover", %{"force" => true})
      |> json!(200)

    assert recover["recovered"] == false
  end

  test "storage compact and backup endpoints are protected and redact paths", %{conn: conn} do
    token = dev_token!(conn)

    compact =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/compact", %{"dryRun" => true})
      |> json!(200)

    assert compact["compact"]["status"] == "ok"
    assert compact["compact"]["dryRun"] == true
    assert Enum.any?(compact["compact"]["files"], &(&1["file"] == "catalog/manifest.tdb"))
    assert_public_hygiene!(compact)

    backup =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/backup", %{
        "include" => ["catalog", "workspaces"],
        "verify" => true
      })
      |> json!(200)

    assert backup["backup"]["format"] == "tar.zst"
    assert backup["backup"]["uri"] =~ "treedb://backup/"
    assert backup["backup"]["verified"] == true
    assert_public_hygiene!(backup)
  end

  test "store lock rejects live pid and replaces stale pid" do
    original = Application.get_env(:treedb, :data_dir)

    data_dir =
      Path.join(System.tmp_dir!(), "treedb-lock-test-#{System.unique_integer([:positive])}")

    {pid, 0} = System.cmd("sh", ["-c", "sleep 10 > /dev/null 2>&1 & echo $!"])
    live_pid = String.trim(pid)

    try do
      File.rm_rf!(data_dir)
      File.mkdir_p!(data_dir)
      Application.put_env(:treedb, :data_dir, data_dir)
      File.write!(Path.join(data_dir, ".treedb.lock"), "#{live_pid}\n")

      assert_raise RuntimeError, ~r/already locked/, fn ->
        TreeDb.Store.init!(node_id: "node_local")
      end

      File.write!(Path.join(data_dir, ".treedb.lock"), "99999999\n")
      report = TreeDb.Store.init!(node_id: "node_local")
      assert report["dataDir"] == data_dir
      assert File.read!(Path.join(data_dir, ".treedb.lock")) == "#{System.pid()}\n"
    after
      System.cmd("kill", [live_pid], stderr_to_stdout: true)

      if original,
        do: Application.put_env(:treedb, :data_dir, original),
        else: Application.delete_env(:treedb, :data_dir)
    end
  end
end
