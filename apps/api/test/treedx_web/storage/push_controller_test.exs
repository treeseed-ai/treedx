defmodule TreeDxWeb.PushControllerTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    data_dir = TreeDx.Store.data_dir()
    repo_path = Path.join(data_dir, "repos/bare/push-api")
    remote_path = Path.join(data_dir, "repos/bare/push-api-remote.git")
    create_git_repo!(repo_path)
    File.rm_rf!(remote_path)
    File.mkdir_p!(remote_path)
    git!(remote_path, ["init", "--bare"])
    token = dev_token!(conn)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "push-api",
        "localPath" => repo_path,
        "remoteUrl" => "file://#{remote_path}"
      })["repo"]

    {:ok, token: token, repo_id: repo["repoId"], remote_path: remote_path}
  end

  test "actor with git push can plan and push an allowed ref", %{
    token: token,
    repo_id: repo_id,
    remote_path: remote_path
  } do
    plan =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "planOnly" => true
      })
      |> json!(200)

    assert plan["push"]["status"] == "plan"
    assert plan["push"]["backend"] == "gix"
    assert_public_hygiene!(plan)

    pushed =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "planOnly" => false
      })
      |> json!(200)

    assert pushed["push"]["status"] == "pushed"
    assert pushed["push"]["updatedRefs"] == ["refs/heads/main"]
    assert git_bare!(remote_path, ["rev-parse", "refs/heads/main"]) =~ ~r/^[0-9a-f]{40}/
  end

  test "push rejects credentials, missing capability, and wrong ref scope", %{
    token: token,
    repo_id: repo_id
  } do
    credential =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "remoteUrl" => "https://token@example.invalid/repo.git",
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "planOnly" => true
      })
      |> json!(422)

    assert credential["error"]["code"] == "validation_error"

    limited_token =
      actor_token!("actor_push_limited", repo_id, ["repos:read"], ["refs/heads/main"])

    denied =
      build_conn()
      |> auth_conn(limited_token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "planOnly" => true
      })
      |> json!(403)

    assert denied["error"]["code"] == "permission_denied"

    scoped_token =
      actor_token!("actor_push_scoped", repo_id, ["git:push"], ["refs/heads/release"])

    wrong_ref =
      build_conn()
      |> auth_conn(scoped_token)
      |> post("/api/v1/repos/#{repo_id}/push", %{
        "refspecs" => ["refs/heads/main:refs/heads/main"],
        "planOnly" => true
      })
      |> json!(403)

    assert wrong_ref["error"]["code"] == "permission_denied"
  end

  test "managed ref promotion can resume after the reviewed commit was already promoted" do
    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/promote-repeat")
    create_git_repo!(repo_path)
    base = String.trim(git!(repo_path, ["rev-parse", "refs/heads/main"]))
    git!(repo_path, ["checkout", "-b", "authoring/repeat"])
    File.write!(Path.join(repo_path, "resume.md"), "resume safely\n")
    git!(repo_path, ["add", "resume.md"])
    git!(repo_path, ["commit", "-m", "resume publication"])

    assert {:ok, %{"status" => "promoted", "beforeHead" => ^base}} =
             TreeDx.Git.promote_ref(
               repo_path,
               "refs/heads/authoring/repeat",
               "refs/heads/main",
               base
             )

    assert {:ok, %{"status" => "already_current", "afterHead" => target}} =
             TreeDx.Git.promote_ref(
               repo_path,
               "refs/heads/authoring/repeat",
               "refs/heads/main",
               base
             )

    assert target == String.trim(git!(repo_path, ["rev-parse", "refs/heads/main"]))
  end

  test "merged ref retirement is exact, safe, and idempotent" do
    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/retire-repeat")
    create_git_repo!(repo_path)
    git!(repo_path, ["checkout", "-b", "authoring/retire"])
    File.write!(Path.join(repo_path, "retire.md"), "retire safely\n")
    git!(repo_path, ["add", "retire.md"])
    git!(repo_path, ["commit", "-m", "retire publication"])
    head = String.trim(git!(repo_path, ["rev-parse", "refs/heads/authoring/retire"]))
    git!(repo_path, ["checkout", "main"])
    git!(repo_path, ["merge", "--ff-only", "authoring/retire"])

    assert {:ok, %{"status" => "retired", "head" => ^head}} =
             TreeDx.Git.retire_ref(
               repo_path,
               "refs/heads/authoring/retire",
               "refs/heads/main",
               head,
               head
             )

    assert {:ok, %{"status" => "already_retired"}} =
             TreeDx.Git.retire_ref(
               repo_path,
               "refs/heads/authoring/retire",
               "refs/heads/main",
               head,
               head
             )

    git!(repo_path, ["checkout", "-b", "authoring/unmerged"])
    File.write!(Path.join(repo_path, "unmerged.md"), "do not retire\n")
    git!(repo_path, ["add", "unmerged.md"])
    git!(repo_path, ["commit", "-m", "unmerged publication"])
    unmerged = String.trim(git!(repo_path, ["rev-parse", "refs/heads/authoring/unmerged"]))

    assert {:error, %{code: "conflict"}} =
             TreeDx.Git.retire_ref(
               repo_path,
               "refs/heads/authoring/unmerged",
               "refs/heads/main",
               unmerged,
               head
             )
  end

  test "orphan ref discard requires policy authority, an exact head, and a reason", %{
    token: token
  } do
    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/orphan-discard")
    create_git_repo!(repo_path)

    repo =
      register_repo!(build_conn(), token, %{
        "name" => "orphan-discard",
        "localPath" => repo_path
      })["repo"]

    repo_id = repo["repoId"]
    git!(repo_path, ["checkout", "-b", "authoring/orphan"])
    File.write!(Path.join(repo_path, "orphan.md"), "abandoned work\n")
    git!(repo_path, ["add", "orphan.md"])
    git!(repo_path, ["commit", "-m", "orphan work"])
    head = String.trim(git!(repo_path, ["rev-parse", "refs/heads/authoring/orphan"]))

    ordinary =
      actor_token!("actor_orphan_ordinary", repo_id, ["git:push"], ["refs/heads/authoring/orphan"])

    denied =
      build_conn()
      |> auth_conn(ordinary)
      |> post("/api/v1/repos/#{repo_id}/refs/discard-orphan", %{
        "ref" => "refs/heads/authoring/orphan",
        "expectedHead" => head,
        "reason" => "Operator-confirmed orphan"
      })
      |> json!(403)

    assert denied["error"]["code"] == "permission_denied"

    maintainer =
      actor_token!("actor_orphan_maintainer", repo_id, ["git:push", "policy:write"], [
        "refs/heads/authoring/orphan"
      ])

    stale =
      build_conn()
      |> auth_conn(maintainer)
      |> post("/api/v1/repos/#{repo_id}/refs/discard-orphan", %{
        "ref" => "refs/heads/authoring/orphan",
        "expectedHead" => String.duplicate("0", 40),
        "reason" => "Operator-confirmed orphan"
      })
      |> json!(409)

    assert stale["error"]["code"] == "conflict"

    discarded =
      build_conn()
      |> auth_conn(maintainer)
      |> post("/api/v1/repos/#{repo_id}/refs/discard-orphan", %{
        "ref" => "refs/heads/authoring/orphan",
        "expectedHead" => head,
        "reason" => "Operator-confirmed orphan"
      })
      |> json!(200)

    assert discarded["discard"]["status"] == "discarded"
    assert discarded["discard"]["head"] == head

    replay =
      build_conn()
      |> auth_conn(maintainer)
      |> post("/api/v1/repos/#{repo_id}/refs/discard-orphan", %{
        "ref" => "refs/heads/authoring/orphan",
        "expectedHead" => head,
        "reason" => "Idempotent cleanup retry"
      })
      |> json!(200)

    assert replay["discard"]["status"] == "already_discarded"
  end

  test "mirror health and promotion plan are audited and protected", %{
    token: token,
    repo_id: repo_id
  } do
    mirror =
      create_mirror!(build_conn(), token, repo_id, %{
        "sourceNodeId" => "node_local",
        "targetNodeId" => "node_mirror",
        "status" => "synced",
        "behindBy" => 0
      })["mirror"]

    health =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/mirrors/#{mirror["id"]}/health", %{})
      |> json!(200)

    assert health["health"]["status"] == "healthy"

    promotion =
      build_conn()
      |> auth_conn(token)
      |> post("/api/v1/repos/#{repo_id}/mirrors/#{mirror["id"]}/promote", %{
        "planOnly" => true,
        "requireSynced" => true
      })
      |> json!(200)

    assert promotion["promotion"]["status"] == "planned"
    assert promotion["promotion"]["resultingPlacement"]["primaryNodeId"] == "node_mirror"
    assert_public_hygiene!(promotion)
  end

  defp actor_token!(actor_id, repo_id, caps, refs) do
    {:ok, _grant} =
      TreeDx.Capabilities.put_grant(%{
        "actorId" => actor_id,
        "tenantId" => "tenant_demo",
        "repoIds" => [repo_id],
        "capabilities" => caps,
        "refs" => refs,
        "paths" => ["**"]
      })

    dev_token!(build_conn(), %{"actorId" => actor_id, "tenantId" => "tenant_demo"})
  end

  defp git_bare!(repo_path, args) do
    {output, status} =
      System.cmd("git", ["--git-dir", repo_path | args], stderr_to_stdout: true)

    assert status == 0, output
    output
  end
end
