defmodule TreeDxWeb.OpenApiContractTest do
  use TreeDxWeb.ConnCase, async: false

  alias TreeDxWeb.OpenApiContractAssertions

  setup %{conn: conn} do
    token =
      conn
      |> post("/api/v1/auth/dev-token", %{})
      |> json_response(200)
      |> Map.fetch!("accessToken")

    {:ok, token: token, openapi: OpenApiContractAssertions.openapi()}
  end

  test "validates health and auth success envelopes", %{
    conn: conn,
    openapi: openapi,
    token: token
  } do
    health =
      conn
      |> get("/api/v1/health")
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :get,
      "/api/v1/health",
      health
    )

    readiness =
      build_conn()
      |> get("/api/v1/ready")
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :get,
      "/api/v1/ready",
      readiness
    )

    deep =
      build_conn()
      |> get("/api/v1/health/deep")
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :get,
      "/api/v1/health/deep",
      deep
    )

    metrics =
      build_conn()
      |> get("/api/v1/metrics")
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :get,
      "/api/v1/metrics",
      metrics
    )

    whoami =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/auth/whoami")
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :get,
      "/api/v1/auth/whoami",
      whoami
    )
  end

  test "validates a protected error envelope", %{openapi: openapi} do
    payload =
      build_conn()
      |> get("/api/v1/repos")
      |> json_response(401)

    OpenApiContractAssertions.assert_matches_error_schema!(
      openapi,
      :get,
      "/api/v1/repos",
      payload
    )
  end

  test "validates repository and workspace success envelopes", %{openapi: openapi, token: token} do
    repo_path = Path.join(TreeDx.Store.data_dir(), "repos/bare/openapi-contract")
    File.rm_rf!(repo_path)
    File.mkdir_p!(repo_path)
    git(repo_path, ["init", "-b", "main"])
    git(repo_path, ["config", "user.name", "TreeDX Test"])
    git(repo_path, ["config", "user.email", "test@example.invalid"])
    File.write!(Path.join(repo_path, "README.md"), "contract\\n")
    git(repo_path, ["add", "README.md"])
    git(repo_path, ["commit", "-m", "initial"])

    repo =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/register", %{"name" => "openapi-contract", "localPath" => repo_path})
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :post,
      "/api/v1/repos/register",
      repo
    )

    repo_id = get_in(repo, ["repo", "repoId"])

    workspace =
      build_conn()
      |> auth(token)
      |> post("/api/v1/repos/#{repo_id}/workspaces", %{
        "baseRef" => "refs/heads/main",
        "branchName" => "refs/heads/agent/contract-workspace",
        "mode" => "writable"
      })
      |> json_response(200)

    OpenApiContractAssertions.assert_matches_success_schema!(
      openapi,
      :post,
      "/api/v1/repos/{repo_id}/workspaces",
      workspace
    )
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp git(path, args) do
    {_, 0} = System.cmd("git", args, cd: path, stderr_to_stdout: true)
  end
end
