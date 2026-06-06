defmodule TreeDxWeb.AdminStorageCompactionBackupTest do
  use TreeDxWeb.ConnCase, async: false

  test "compact and backup responses expose logical metadata only", %{conn: conn} do
    token = dev_token!(conn)

    compact =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/compact", %{"dryRun" => true})
      |> json!(200)

    assert compact["compact"]["status"] == "ok"
    assert Enum.all?(compact["compact"]["files"], &(not String.starts_with?(&1["file"], "/")))
    assert_public_hygiene!(compact)

    backup =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/backup", %{"include" => ["catalog"], "verify" => true})
      |> json!(200)

    assert backup["backup"]["uri"] =~ "treedx://backup/"
    assert backup["backup"]["verified"] == true
    assert_public_hygiene!(backup)
  end

  test "compact and backup enforce capabilities" do
    build_conn()
    |> post("/api/v1/admin/storage/compact", %{"dryRun" => true})
    |> json_response(401)

    build_conn()
    |> post("/api/v1/admin/storage/backup", %{"verify" => true})
    |> json_response(401)
  end
end
