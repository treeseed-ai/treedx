defmodule TreeDxWeb.AdminStorageMigrationRestoreTest do
  use TreeDxWeb.ConnCase, async: false

  test "migration and restore routes are capability-gated and sanitized", %{conn: conn} do
    token = dev_token!(conn)

    plan =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/migrations/plan", %{"targetVersion" => "contract_v2"})
      |> json!(200)

    assert plan["migration"]["status"] == "planned"
    assert Enum.all?(plan["migration"]["logs"], &(not String.starts_with?(&1, "/")))
    assert_public_hygiene!(plan)

    apply =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/migrations/apply", %{
        "targetVersion" => "contract_v2",
        "backupBefore" => false
      })
      |> json!(200)

    assert apply["migration"]["status"] == "applied"
    assert_public_hygiene!(apply)

    rollback =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/migrations/rollback", %{
        "migrationId" => apply["migration"]["migrationId"]
      })
      |> json!(200)

    assert rollback["migration"]["status"] == "rolled_back"
    assert_public_hygiene!(rollback)

    backup =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/backup", %{"verify" => true})
      |> json!(200)

    verify =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/restore/verify", %{
        "backupId" => backup["backup"]["backupId"]
      })
      |> json!(200)

    assert verify["restore"]["verified"] == true
    assert verify["restore"]["uri"] =~ "treedx://backup/"
    assert_public_hygiene!(verify)
  end

  test "restore apply requires explicit enablement or dry run", %{conn: conn} do
    token = dev_token!(conn)

    response =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/admin/storage/restore", %{"backupId" => "backup_missing"})
      |> json_response(403)

    assert response["error"]["code"] == "permission_denied"
    assert_public_hygiene!(response)
  end
end
