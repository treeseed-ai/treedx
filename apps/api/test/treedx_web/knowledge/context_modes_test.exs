defmodule TreeDxWeb.ContextModesTest do
  use TreeDxWeb.ConnCase, async: false

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/context-modes")
    create_fixture(repo_path)

    repo_id =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "context-modes", "localPath" => repo_path})
      |> json_response(200)
      |> get_in(["repo", "repoId"])

    build_conn()
    |> auth(token)
    |> post("/api/v1/repos/#{repo_id}/graph/refresh", %{"paths" => ["docs/**"]})
    |> json_response(200)

    {:ok, token: token, repo_id: repo_id}
  end

  test "context modes produce bounded diagnostics and provenance", %{
    token: token,
    repo_id: repo_id
  } do
    for mode <- ["brief", "detailed", "citations", "mixed"] do
      context =
        build_conn()
        |> auth(token)
        |> post("/api/v1/repos/#{repo_id}/context/build", %{
          "query" => "release",
          "scope" => "sections",
          "mode" => mode,
          "budget" => %{"maxNodes" => 2, "maxTokens" => 80},
          "options" => %{"limit" => 10}
        })
        |> json_response(200)

      assert context["mode"] == mode
      assert length(context["nodes"]) <= 2
      assert context["totalTokenEstimate"] <= 80
      assert context["diagnostics"]["budget"]["requestedMaxNodes"] == 2
      assert is_list(context["diagnostics"]["provenancePaths"])
      refute inspect(context) =~ TreeDx.Store.data_dir()
    end
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_fixture(path) do
    File.rm_rf!(path)
    File.mkdir_p!(Path.join(path, "docs"))
    git(path, ["init", "-b", "main"])
    git(path, ["config", "user.name", "TreeDX Test"])
    git(path, ["config", "user.email", "test@example.invalid"])

    File.write!(Path.join(path, "docs/readme.md"), """
    # Readme

    Release context overview.

    ## Details

    Detailed release context and citations.
    """)

    git(path, ["add", "."])
    git(path, ["commit", "-m", "init"])
  end

  defp git(cwd, args) do
    {output, status} = System.cmd("git", args, cd: cwd, stderr_to_stdout: true)
    assert status == 0, "git #{inspect(args)} failed: #{output}"
  end
end
